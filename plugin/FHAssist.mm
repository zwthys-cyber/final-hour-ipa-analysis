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

@interface FHPassthroughWindow : UIWindow
@end
@implementation FHPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v=[super hitTest:point withEvent:event];
    return v==self || v==self.rootViewController.view ? nil : v;
}
@end

@interface FHRootController : UIViewController
@end
@implementation FHRootController
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
@end

@interface FHAssistController : NSObject {
    uintptr_t _settings;
    fh::Session _session;
    fh::Options _options;
}
@property(nonatomic,strong) FHPassthroughWindow *window;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIButton *bubble;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *followLabel;
@property(nonatomic,strong) UILabel *rangeLabel;
@property(nonatomic,strong) UILabel *paddingLabel;
@property(nonatomic,strong) UISwitch *master;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL enabled;
- (void)install;
@end

@implementation FHAssistController
- (fh::Words)readSettings {
    fh::Words w{};
    auto words=reinterpret_cast<uint32_t *>(_settings);
    for(size_t i=0;i<w.size();++i) w[i]=__atomic_load_n(words+i,__ATOMIC_RELAXED);
    return w;
}
- (BOOL)apply {
    if(!_settings || !Readable(_settings,sizeof(fh::Words),true)) return NO;
    auto current=[self readSettings];
    if(!_session.begin(current)) return NO;
    auto desired=_session.desired(current,_options);
    auto words=reinterpret_cast<uint32_t *>(_settings);
    for(size_t i:fh::kWordIndices) __atomic_store_n(words+i,desired[i],__ATOMIC_RELAXED);
    return YES;
}
- (void)restore {
    if(!_session.active) return;
    if(_settings && Readable(_settings,sizeof(fh::Words),true)) {
        auto words=reinterpret_cast<uint32_t *>(_settings);
        // Compare-and-swap keeps changes made by the game after our last write.
        for(size_t i:fh::kWordIndices) {
            uint32_t expected=_session.last[i];
            __atomic_compare_exchange_n(words+i,&expected,_session.original[i],false,__ATOMIC_RELAXED,__ATOMIC_RELAXED);
        }
    }
    _session.active=false;
}
- (void)tick {
    if(self.enabled && ![self apply]) {
        self.enabled=NO;self.master.on=NO;[self restore];
        self.status.text=@"参数检查失败，增强已关闭";
    }
}
- (void)toggle:(UISwitch *)sender {
    self.enabled=sender.on;
    if(self.enabled && ![self apply]) {
        self.enabled=NO;sender.on=NO;[self restore];
        self.status.text=@"当前游戏状态无法启用";return;
    }
    if(!self.enabled) [self restore];
    self.status.text=self.enabled?@"增强已开启 · 沿用游戏目标判定":@"增强已关闭 · 已恢复原参数";
}
- (UILabel *)label:(NSString *)text {
    UILabel *l=[UILabel new];l.text=text;l.textColor=UIColor.whiteColor;
    l.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];return l;
}
- (UIStackView *)row:(UIView *)left right:(UIView *)right {
    UIStackView *r=[[UIStackView alloc] initWithArrangedSubviews:@[left,right]];
    r.axis=UILayoutConstraintAxisHorizontal;r.alignment=UIStackViewAlignmentCenter;r.distribution=UIStackViewDistributionEqualSpacing;return r;
}
- (UISlider *)slider:(float)value min:(float)lo max:(float)hi tag:(NSInteger)tag {
    UISlider *s=[UISlider new];s.minimumValue=lo;s.maximumValue=hi;s.value=value;s.tag=tag;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];return s;
}
- (void)updateLabels {
    self.followLabel.text=[NSString stringWithFormat:@"跟随强度 %.2f",_options.follow];
    self.rangeLabel.text=[NSString stringWithFormat:@"目标距离 %.0f 米",_options.rangeMeters];
    self.paddingLabel.text=[NSString stringWithFormat:@"捕获范围 %.0f 厘米",_options.paddingCm];
}
- (void)sliderChanged:(UISlider *)sender {
    if(sender.tag==0)_options.follow=sender.value;
    if(sender.tag==1)_options.rangeMeters=sender.value;
    if(sender.tag==2)_options.paddingCm=sender.value;
    [self updateLabels];[self tick];
}
- (void)adsChanged:(UISwitch *)sender { _options.adsOnly=sender.on;[self tick]; }
- (void)showPanel { self.panel.hidden=!self.panel.hidden; }
- (void)drag:(UIPanGestureRecognizer *)gesture {
    CGPoint translation=[gesture translationInView:self.window.rootViewController.view];
    CGPoint center=self.bubble.center;
    CGFloat w=self.window.bounds.size.width,h=self.window.bounds.size.height;
    self.bubble.center=CGPointMake(std::max(CGFloat(28),std::min(w-28,center.x+translation.x)),
        std::max(CGFloat(28),std::min(h-28,center.y+translation.y)));
    [gesture setTranslation:CGPointZero inView:self.window.rootViewController.view];
}
- (void)install {
    if(self.window) return;
    UIWindowScene *scene=nil;
    for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState==UISceneActivationStateForegroundActive) {
            scene=(UIWindowScene *)candidate;break;
        }
    }
    if(!scene) return;
    _settings=LocateSettings();
    if(_settings && !fh::plausible([self readSettings])) _settings=0;
    self.window=[[FHPassthroughWindow alloc] initWithWindowScene:scene];
    self.window.frame=scene.coordinateSpace.bounds;self.window.backgroundColor=UIColor.clearColor;
    self.window.windowLevel=UIWindowLevelAlert+1;
    FHRootController *root=[FHRootController new];root.view.backgroundColor=UIColor.clearColor;self.window.rootViewController=root;
    self.bubble=[UIButton buttonWithType:UIButtonTypeSystem];self.bubble.frame=CGRectMake(24,70,48,48);
    [self.bubble setTitle:@"FH" forState:UIControlStateNormal];[self.bubble setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.bubble.backgroundColor=[UIColor colorWithRed:.12 green:.55 blue:.7 alpha:.9];self.bubble.layer.cornerRadius=24;
    [self.bubble addTarget:self action:@selector(showPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    self.bubble.accessibilityLabel=@"打开 FH 辅助设置";[root.view addSubview:self.bubble];
    self.panel=[UIView new];self.panel.translatesAutoresizingMaskIntoConstraints=NO;
    self.panel.backgroundColor=[UIColor colorWithWhite:.08 alpha:.96];self.panel.layer.cornerRadius=16;self.panel.hidden=YES;[root.view addSubview:self.panel];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.panel addSubview:scroll];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];[close setTitle:@"收起" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(showPanel) forControlEvents:UIControlEventTouchUpInside];
    self.master=[UISwitch new];self.master.enabled=(_settings!=0);self.master.on=NO;
    [self.master addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    self.status=[self label:_settings?@"支持当前版本 · 增强默认关闭":@"此游戏版本不支持，未修改参数"];self.status.numberOfLines=0;
    UISwitch *ads=[UISwitch new];ads.on=YES;[ads addTarget:self action:@selector(adsChanged:) forControlEvents:UIControlEventValueChanged];
    self.followLabel=[self label:@""];self.rangeLabel=[self label:@""];self.paddingLabel=[self label:@""];[self updateLabels];
    UILabel *note=[self label:@"增强游戏原生辅助；沿用可见性、目标部位和移动条件。关闭开关可恢复参数。"];note.numberOfLines=0;note.font=[UIFont systemFontOfSize:11];note.textColor=UIColor.lightGrayColor;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[
        [self row:[self label:@"FH 原生跟瞄增强"] right:close],self.status,
        [self row:[self label:@"启用增强"] right:self.master],
        [self row:[self label:@"仅开镜时启用"] right:ads],
        self.followLabel,[self slider:_options.follow min:.5 max:2 tag:0],
        self.rangeLabel,[self slider:_options.rangeMeters min:20 max:150 tag:1],
        self.paddingLabel,[self slider:_options.paddingCm min:20 max:200 tag:2],note]];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=6;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.panel.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [self.panel.centerYAnchor constraintEqualToAnchor:root.view.centerYAnchor],
        [self.panel.widthAnchor constraintEqualToConstant:330],
        [self.panel.heightAnchor constraintEqualToAnchor:root.view.safeAreaLayoutGuide.heightAnchor multiplier:.9],
        [scroll.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:14],
        [scroll.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-14],
        [scroll.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    self.window.hidden=NO; // Do not make the overlay key: keyboard/game focus remains with the game.
    self.timer=[NSTimer scheduledTimerWithTimeInterval:.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}
@end

static FHAssistController *gController;
__attribute__((constructor)) static void FHAssistLoad() {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(),^{
            gController=[FHAssistController new];
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
                [gController install];if(gController.window)[timer invalidate];
            }];
        });
    }
}
