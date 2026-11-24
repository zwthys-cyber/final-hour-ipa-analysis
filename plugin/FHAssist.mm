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
@property(nonatomic,strong) UIButton *fireButton;
@property(nonatomic,strong) UIButton *zoomButton;
@property(nonatomic,strong) UILabel *report;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) uint64_t lastFrames;
@property(nonatomic) NSTimeInterval lastHeartbeatTime;
- (void)install;
@end
@implementation FHRadarController
- (void)refresh {
    BOOL on=radar::enabled.load(),head=radar::headEnabled.load();
    BOOL attached=(on || head || radar::zoomOut.load() || radar::fireOwned.load()) && radar::attach();
    [self.button setTitle:on?(attached?@"地图敌人：开":@"地图：等待对局"):@"地图敌人：关" forState:UIControlStateNormal];
    [self.headButton setTitle:head?(attached?@"锁头：搜敌中":@"锁头：等待对局"):@"锁头：关" forState:UIControlStateNormal];
    [self.zoomButton setTitle:radar::zoomOut.load()?@"地图比例：缩小 2 倍":@"地图比例：原始" forState:UIControlStateNormal];
    [self.fireButton setTitle:radar::fireEnabled.load()?(radar::fireOwned.load()?@"自动开火：输入中":@"自动开火：等待对准"):@"自动开火：关" forState:UIControlStateNormal];
    uint64_t frames=radar::hudFrames.load();
    NSTimeInterval now=NSDate.timeIntervalSinceReferenceDate;
    if(frames!=self.lastFrames) self.lastHeartbeatTime=now;
    self.lastFrames=frames;
    NSString *states[] = {@"锁头未启用",@"正在检查角色",@"未获取到本地角色",@"未获取到有效镜头",@"本地角色未存活",@"骨骼类型初始化失败",@"没有存活敌人",@"敌人网格缺少 head 骨骼",@"目标超出角度或距离",@"目标未通过视线检查",@"已写入头部瞄准视角",@"视角写入核对失败",@"本地角色缺少开火组件"};
    unsigned state=radar::headState.load();
    NSString *reason=state<13?states[state]:@"等待检查";
    if(!attached) reason=@"等待进入支持的对局";
    else if(!frames || now-self.lastHeartbeatTime>=2) reason=@"HUD 回调未运行或已暂停";
    self.report.text=[NSString stringWithFormat:@"FH 0.3 · %@\n回调 %llu · 敌 %u · 头 %u · 范围 %u · 可见 %u · 写视角 %llu",reason,
        (unsigned long long)frames,radar::enemyCount.load(),radar::boneCount.load(),radar::angleCount.load(),
        radar::visibleCount.load(),(unsigned long long)radar::viewWrites.load()];
}
- (void)toggle { radar::enabled.store(!radar::enabled.load());[self refresh]; }
- (void)toggleHead {
    BOOL on=!radar::headEnabled.load();radar::headEnabled.store(on);
    if(!on) radar::fireEnabled.store(false);
    [self refresh];
}
- (void)toggleFire {
    BOOL on=!radar::fireEnabled.load();
    if(on) radar::headEnabled.store(true);
    radar::fireEnabled.store(on);[self refresh];
}
- (void)toggleZoom { radar::zoomOut.store(!radar::zoomOut.load());[self refresh]; }
- (void)copyReport {
    UIPasteboard.generalPasteboard.string=[NSString stringWithFormat:@"%@\n地图 %d / 锁头 %d / 缩图 %d / 自动火 %d",self.report.text,
        radar::enabled.load(),radar::headEnabled.load(),radar::zoomOut.load(),radar::fireEnabled.load()];
    self.report.text=@"运行状态已复制，可粘贴反馈";
}
- (void)suspend { radar::fireEnabled.store(false);radar::headEnabled.store(false); }
- (UIButton *)makeButton:(SEL)action label:(NSString *)label root:(UIView *)root column:(CGFloat)column row:(CGFloat)row {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.translatesAutoresizingMaskIntoConstraints=NO;
    b.backgroundColor=[UIColor colorWithWhite:.08 alpha:.85];b.layer.cornerRadius=9;
    b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];b.accessibilityLabel=label;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[root addSubview:b];
    [NSLayoutConstraint activateConstraints:@[
        [b.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:8+40*row],
        [b.centerXAnchor constraintEqualToAnchor:root.centerXAnchor constant:column*94],
        [b.widthAnchor constraintEqualToConstant:180],[b.heightAnchor constraintEqualToConstant:34]
    ]];return b;
}
- (void)install {
    if(self.window) return;
    UIWindowScene *scene=nil;
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if([s isKindOfClass:UIWindowScene.class] && s.activationState==UISceneActivationStateForegroundActive) {
            scene=(UIWindowScene *)s;break;
        }
    if(!scene) return;
    BOOL supported=LocateSettings()!=0;
    if(supported) radar::base=reinterpret_cast<uintptr_t>(_dyld_get_image_header(0));
    self.window=[[FHRadarWindow alloc] initWithWindowScene:scene];
    self.window.frame=scene.coordinateSpace.bounds;self.window.windowLevel=UIWindowLevelAlert+1;
    self.window.backgroundColor=UIColor.clearColor;
    FHRadarRoot *root=[FHRadarRoot new];root.view.backgroundColor=UIColor.clearColor;
    self.window.rootViewController=root;
    self.button=[self makeButton:@selector(toggle) label:@"小地图敌人持续显示" root:root.view column:-1 row:0];
    self.headButton=[self makeButton:@selector(toggleHead) label:@"头部瞄准" root:root.view column:1 row:0];
    self.zoomButton=[self makeButton:@selector(toggleZoom) label:@"缩小地图内容比例" root:root.view column:-1 row:1];
    self.fireButton=[self makeButton:@selector(toggleFire) label:@"对准后自动开火" root:root.view column:1 row:1];
    self.report=[UILabel new];self.report.translatesAutoresizingMaskIntoConstraints=NO;
    self.report.textColor=UIColor.whiteColor;self.report.backgroundColor=[UIColor colorWithWhite:.08 alpha:.8];
    self.report.font=[UIFont systemFontOfSize:11];self.report.numberOfLines=2;self.report.textAlignment=NSTextAlignmentCenter;
    self.report.userInteractionEnabled=YES;self.report.accessibilityLabel=@"运行状态，轻点复制诊断";
    [self.report addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyReport)]];
    [root.view addSubview:self.report];
    [NSLayoutConstraint activateConstraints:@[
        [self.report.topAnchor constraintEqualToAnchor:self.zoomButton.bottomAnchor constant:5],
        [self.report.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [self.report.widthAnchor constraintEqualToConstant:374],[self.report.heightAnchor constraintEqualToConstant:40]
    ]];
    for(UIButton *b in @[self.button,self.headButton,self.zoomButton,self.fireButton]) {
        b.enabled=supported;
        if(!supported) [b setTitle:@"版本不支持" forState:UIControlStateNormal];
    }
    if(supported) [self refresh];else self.report.text=@"FH 0.3 · 游戏版本不支持，未启用";
    self.window.hidden=NO;
    if(supported) {
        self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(suspend) name:UIApplicationWillResignActiveNotification object:nil];
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
