#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#include "AimSettings.hpp"
#include <algorithm>

static bool Readable(uintptr_t address, size_t size, bool writable) {
    vm_address_t region=address;
    vm_size_t length=0;
    vm_region_basic_info_data_64_t info={};
    mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object=MACH_PORT_NULL;
    kern_return_t kr=vm_region_64(mach_task_self(),&region,&length,VM_REGION_BASIC_INFO_64,
        reinterpret_cast<vm_region_info_t>(&info),&count,&object);
    if(object!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),object);
    if(kr!=KERN_SUCCESS || address<region || size>length || address-region>length-size) return false;
    return (info.protection&VM_PROT_READ) && (!writable || (info.protection&VM_PROT_WRITE));
}
static uintptr_t LocateSettings() {
    if(![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.aggames.finalhour"]) return 0;
    const mach_header *raw=_dyld_get_image_header(0);
    if(!raw || raw->magic!=MH_MAGIC_64) return 0;
    auto h=reinterpret_cast<const mach_header_64 *>(raw);
    const uint8_t *cursor=reinterpret_cast<const uint8_t *>(h+1);
    const uint8_t *end=cursor+h->sizeofcmds;
    bool uuidOK=false;
    for(uint32_t i=0;i<h->ncmds;++i) {
        if(cursor+sizeof(load_command)>end) return 0;
        auto c=reinterpret_cast<const load_command *>(cursor);
        if(c->cmdsize<sizeof(load_command) || c->cmdsize>static_cast<size_t>(end-cursor)) return 0;
        if(c->cmd==LC_UUID && c->cmdsize>=sizeof(uuid_command)) {
            auto u=reinterpret_cast<const uuid_command *>(cursor);
            uuidOK=std::memcmp(u->uuid,fh::kUUID.data(),16)==0;
        }
        cursor+=c->cmdsize;
    }
    if(!uuidOK) return 0;
    // Both function prologues must match, in addition to the exact Mach-O UUID.
    const uint8_t tick[]={0xef,0x3b,0xb6,0x6d,0xed,0x33,0x01,0x6d,0xeb,0x2b,0x02,0x6d,0xe9,0x23,0x03,0x6d};
    const uint8_t follow[]={0xff,0x43,0x03,0xd1,0xeb,0x2b,0x07,0x6d,0xe9,0x23,0x08,0x6d,0xf8,0x5f,0x09,0xa9};
    uintptr_t base=reinterpret_cast<uintptr_t>(h);
    uintptr_t a=base+0x07822e7c,b=base+0x07823b90;
    if(!Readable(a,16,false)||!Readable(b,16,false)||std::memcmp(reinterpret_cast<void *>(a),tick,16)||std::memcmp(reinterpret_cast<void *>(b),follow,16)) return 0;
    uintptr_t settings=base+fh::kSettingsOffset;
    return Readable(settings,sizeof(fh::Words),true)?settings:0;
}

#include "Minimap.hpp"

@interface FHRadarWindow : UIWindow
@end
@implementation FHRadarWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v=[super hitTest:point withEvent:event];
    return v==self || v==self.rootViewController.view ? nil : v;
}
@end
@interface FHRadarRoot : UIViewController
@end
@implementation FHRadarRoot
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
@end
@interface FHRadarController : NSObject
@property(nonatomic,strong) FHRadarWindow *window;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) UIButton *headButton;
@property(nonatomic,strong) NSTimer *timer;
- (void)install;
@end
@implementation FHRadarController
- (void)refresh {
    BOOL on=radar::enabled.load();
    BOOL head=radar::headEnabled.load();
    BOOL attached=(on || head) && radar::attach();
    NSString *title=on?(attached?@"地图敌人：开":@"地图敌人：等待对局"):@"地图敌人：关";
    [self.button setTitle:title forState:UIControlStateNormal];
    self.button.accessibilityValue=title;
    NSString *headTitle=head?(attached?@"锁头：开":@"锁头：等待对局"):@"锁头：关";
    [self.headButton setTitle:headTitle forState:UIControlStateNormal];
    self.headButton.accessibilityValue=headTitle;
}
- (void)toggle {
    radar::enabled.store(!radar::enabled.load());[self refresh];
}
- (void)toggleHead {
    radar::headEnabled.store(!radar::headEnabled.load());[self refresh];
}
- (void)install {
    if(self.window) return;
    UIWindowScene *scene=nil;
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if([s isKindOfClass:UIWindowScene.class] && s.activationState==UISceneActivationStateForegroundActive) {
            scene=(UIWindowScene *)s;break;
        }
    if(!scene) return;
    // Retain the existing exact UUID and code-prefix compatibility gate.
    BOOL supported=LocateSettings()!=0;
    if(supported) radar::base=reinterpret_cast<uintptr_t>(_dyld_get_image_header(0));
    self.window=[[FHRadarWindow alloc] initWithWindowScene:scene];
    self.window.frame=scene.coordinateSpace.bounds;self.window.windowLevel=UIWindowLevelAlert+1;
    self.window.backgroundColor=UIColor.clearColor;
    FHRadarRoot *root=[FHRadarRoot new];root.view.backgroundColor=UIColor.clearColor;
    self.window.rootViewController=root;
    self.button=[UIButton buttonWithType:UIButtonTypeSystem];
    self.button.translatesAutoresizingMaskIntoConstraints=NO;
    self.button.backgroundColor=[UIColor colorWithWhite:.08 alpha:.85];self.button.layer.cornerRadius=10;
    self.button.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    self.button.accessibilityLabel=@"切换小地图敌人持续显示";
    [root.view addSubview:self.button];
    [NSLayoutConstraint activateConstraints:@[
        [self.button.topAnchor constraintEqualToAnchor:root.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.button.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [self.button.widthAnchor constraintEqualToConstant:180],
        [self.button.heightAnchor constraintEqualToConstant:36]
    ]];
    self.headButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.headButton.translatesAutoresizingMaskIntoConstraints=NO;
    self.headButton.backgroundColor=[UIColor colorWithWhite:.08 alpha:.85];self.headButton.layer.cornerRadius=10;
    self.headButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.headButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.headButton addTarget:self action:@selector(toggleHead) forControlEvents:UIControlEventTouchUpInside];
    self.headButton.accessibilityLabel=@"切换可见敌人头部瞄准";
    [root.view addSubview:self.headButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.headButton.topAnchor constraintEqualToAnchor:self.button.bottomAnchor constant:6],
        [self.headButton.centerXAnchor constraintEqualToAnchor:self.button.centerXAnchor],
        [self.headButton.widthAnchor constraintEqualToAnchor:self.button.widthAnchor],
        [self.headButton.heightAnchor constraintEqualToAnchor:self.button.heightAnchor]
    ]];
    self.headButton.enabled=supported;
    if(!supported) [self.headButton setTitle:@"锁头：版本不支持" forState:UIControlStateNormal];
    self.button.enabled=supported;
    if(supported) [self refresh];
    else [self.button setTitle:@"地图敌人：版本不支持" forState:UIControlStateNormal];
    self.window.hidden=NO;
    if(supported) {
        self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
}
@end
static FHRadarController *gController;
__attribute__((constructor)) static void FHAssistLoad() {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(),^{
            gController=[FHRadarController new];
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
                [gController install];if(gController.window)[timer invalidate];
            }];
        });
    }
}
