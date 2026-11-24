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
@property(nonatomic,copy) void (^onLayout)(void);
@end
@implementation FHRadarRoot
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews];if(self.onLayout) self.onLayout(); }
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
@end
@interface FHRadarController : NSObject
@property(nonatomic,strong) FHRadarWindow *window;
@property(nonatomic,strong) UIButton *bubble;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic) CGPoint bubblePosition;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) UIButton *headButton;
@property(nonatomic,strong) UIButton *bodyButton;
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
    BOOL on=radar::enabled.load();
    aim::Part part=radar::aimPart.load();
    BOOL head=part==aim::Part::Head,body=part==aim::Part::Body;
    BOOL attached=(on || head || body || radar::zoomOut.load()) && radar::attach();
    [self.button setTitle:on?(attached?@"地图敌人：开":@"地图：等待对局"):@"地图敌人：关" forState:UIControlStateNormal];
    [self.headButton setTitle:head?(attached?@"锁头：搜敌中":@"锁头：等待对局"):@"锁头：关" forState:UIControlStateNormal];
    [self.bodyButton setTitle:body?(attached?@"锁身体：搜敌中":@"锁身体：等待对局"):@"锁身体：关" forState:UIControlStateNormal];
    [self.zoomButton setTitle:radar::zoomOut.load()?@"地图比例：缩小 2 倍":@"地图比例：原始" forState:UIControlStateNormal];
    NSString *fireTitle=radar::fireEnabled.load()?(radar::overlayOpen.load()?@"自动开火：面板内暂停":@"自动开火：严格点射"):@"自动开火：关";
    [self.fireButton setTitle:fireTitle forState:UIControlStateNormal];
    uint64_t frames=radar::hudFrames.load();
    NSTimeInterval now=NSDate.timeIntervalSinceReferenceDate;
    if(frames!=self.lastFrames) self.lastHeartbeatTime=now;
    self.lastFrames=frames;
    NSString *states[] = {@"瞄准未启用",@"正在检查角色",@"未获取到本地角色",@"未获取到有效镜头",@"本地角色未存活",@"骨骼类型初始化失败",@"没有存活敌人",@"网格缺少所选部位骨骼",@"目标超出角度或距离",@"目标未通过视线检查",@"已写入瞄准视角",@"视角写入核对失败",@"本地角色缺少开火组件",@"面板内暂停瞄准与点射"};
    unsigned state=radar::headState.load();
    NSString *reason=state<14?states[state]:@"等待检查";
    if(state==10) reason=[NSString stringWithFormat:@"控制旋转已写 · 镜头差 %.2f°",radar::cameraErrorMilliDegrees.load()/1000.0];
    if(radar::reportedPart.load()!=part) reason=@"正在切换瞄准部位";
    if(!attached) reason=@"等待进入支持的对局";
    else if(!frames || now-self.lastHeartbeatTime>=2) reason=@"HUD 回调未运行或已暂停";
    NSString *rays[]={@"未检查",@"命中所选部位",@"未命中或起点重叠",@"遮挡或命中其他对象",@"命中点偏离所选部位",@"查询不可用"};
    unsigned ray=static_cast<unsigned>(radar::lastRay.load());
    self.report.text=[NSString stringWithFormat:@"FH 0.6 · %@\n回调 %llu · 敌 %u · 骨骼 %u · 范围 %u · 可见 %u · 写视角 %llu\n上次射线：%@ · 点射请求 %llu",reason,
        (unsigned long long)frames,radar::enemyCount.load(),radar::boneCount.load(),radar::angleCount.load(),
        radar::visibleCount.load(),(unsigned long long)radar::viewWrites.load(),ray<6?rays[ray]:@"未知",(unsigned long long)radar::shotRequests.load()];
}
- (void)toggle { radar::enabled.store(!radar::enabled.load());[self refresh]; }
- (void)togglePart:(aim::Part)requested {
    aim::Part next=aim::toggle(radar::aimPart.load(),requested);
    radar::aimPart.store(next);
    if(next==aim::Part::Off) radar::fireEnabled.store(false);
    [self refresh];
}
- (void)toggleHead { [self togglePart:aim::Part::Head]; }
- (void)toggleBody { [self togglePart:aim::Part::Body]; }
- (void)toggleFire {
    BOOL on=!radar::fireEnabled.load();
    if(on) radar::aimPart.store(aim::forAutoFire(radar::aimPart.load()));
    radar::fireEnabled.store(on);[self refresh];
}
- (void)toggleZoom { radar::zoomOut.store(!radar::zoomOut.load());[self refresh]; }
- (void)copyReport {
    UIPasteboard.generalPasteboard.string=[NSString stringWithFormat:@"%@\n地图 %d / 部位 %@ / 缩图 %d / 自动火 %d",self.report.text,
        radar::enabled.load(),radar::aimPart.load()==aim::Part::Body?@"身体":(radar::aimPart.load()==aim::Part::Head?@"头部":@"关闭"),radar::zoomOut.load(),radar::fireEnabled.load()];
    self.report.text=@"运行状态已复制，可粘贴反馈";
}
- (void)suspend { radar::fireEnabled.store(false);radar::aimPart.store(aim::Part::Off); }
- (CGRect)overlayArea {
    UIView *root=self.window.rootViewController.view;
    CGRect safe=UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets);
    return CGRectInset(safe,8,8);
}
- (void)layoutOverlay {
    if(!self.bubble || !self.panel) return;
    CGRect area=[self overlayArea];
    if(area.size.width<32 || area.size.height<32) return;
    self.bubble.frame=CGRectMake(CGRectGetMinX(area)+self.bubblePosition.x*(area.size.width-32),
        CGRectGetMinY(area)+self.bubblePosition.y*(area.size.height-32),32,32);
    CGFloat width=std::min(CGFloat(280),area.size.width),height=std::min(CGFloat(310),area.size.height);
    CGFloat x=CGRectGetMinX(self.bubble.frame)-width-8;
    if(x<CGRectGetMinX(area)) x=CGRectGetMaxX(self.bubble.frame)+8;
    x=std::max(CGRectGetMinX(area),std::min(CGRectGetMaxX(area)-width,x));
    CGFloat y=std::max(CGRectGetMinY(area),std::min(CGRectGetMaxY(area)-height,self.bubble.center.y-height/2));
    self.panel.frame=CGRectMake(x,y,width,height);
}
- (void)togglePanel {
    self.panel.hidden=!self.panel.hidden;
    radar::overlayOpen.store(!self.panel.hidden);
    [self refresh];
    self.bubble.alpha=self.panel.hidden?.55:.9;
    self.bubble.accessibilityLabel=self.panel.hidden?@"展开 FH 设置，可拖动":@"收起 FH 设置，可拖动";
    [self layoutOverlay];
}
- (void)dragBubble:(UIPanGestureRecognizer *)gesture {
    UIView *root=self.window.rootViewController.view;
    CGRect area=[self overlayArea];CGPoint delta=[gesture translationInView:root];
    if(area.size.width<=32 || area.size.height<=32) return;
    self.bubblePosition=CGPointMake(
        std::max(CGFloat(0),std::min(CGFloat(1),self.bubblePosition.x+delta.x/(area.size.width-32))),
        std::max(CGFloat(0),std::min(CGFloat(1),self.bubblePosition.y+delta.y/(area.size.height-32))));
    [gesture setTranslation:CGPointZero inView:root];[self layoutOverlay];
    if(gesture.state==UIGestureRecognizerStateEnded)
        [NSUserDefaults.standardUserDefaults setObject:@{@"x":@(self.bubblePosition.x),@"y":@(self.bubblePosition.y)} forKey:@"FHAssist.overlayPosition.v1"];
}
- (UIButton *)makeButton:(SEL)action label:(NSString *)label root:(UIView *)root {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.translatesAutoresizingMaskIntoConstraints=NO;
    b.backgroundColor=[UIColor colorWithWhite:.18 alpha:1];b.layer.cornerRadius=8;
    b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];b.accessibilityLabel=label;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[root addSubview:b];
    [b.heightAnchor constraintEqualToConstant:34].active=YES;return b;
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
    self.panel=[UIView new];self.panel.backgroundColor=[UIColor colorWithWhite:.06 alpha:.94];
    self.panel.layer.cornerRadius=12;self.panel.clipsToBounds=YES;self.panel.hidden=YES;
    [root.view addSubview:self.panel];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    [self.panel addSubview:scroll];
    self.button=[self makeButton:@selector(toggle) label:@"小地图敌人持续显示" root:scroll];
    self.headButton=[self makeButton:@selector(toggleHead) label:@"头部瞄准" root:scroll];
    self.bodyButton=[self makeButton:@selector(toggleBody) label:@"身体瞄准，与锁头互斥" root:scroll];
    self.zoomButton=[self makeButton:@selector(toggleZoom) label:@"缩小地图内容比例" root:scroll];
    self.fireButton=[self makeButton:@selector(toggleFire) label:@"对准后自动开火" root:scroll];
    UILabel *title=[UILabel new];title.text=@"FH 0.6";title.textColor=UIColor.whiteColor;
    title.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];[close setTitle:@"收起" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[title,close]];
    header.distribution=UIStackViewDistributionEqualSpacing;header.alignment=UIStackViewAlignmentCenter;
    self.report=[UILabel new];self.report.translatesAutoresizingMaskIntoConstraints=NO;
    self.report.textColor=UIColor.lightGrayColor;self.report.font=[UIFont systemFontOfSize:11];self.report.numberOfLines=0;
    self.report.userInteractionEnabled=YES;self.report.accessibilityLabel=@"运行状态，轻点复制诊断";
    [self.report addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyReport)]];
    UIStackView *parts=[[UIStackView alloc] initWithArrangedSubviews:@[self.headButton,self.bodyButton]];
    parts.axis=UILayoutConstraintAxisHorizontal;parts.spacing=7;parts.distribution=UIStackViewDistributionFillEqually;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,self.button,parts,self.zoomButton,self.fireButton,self.report]];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=7;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.panel.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-10],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-10],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-20]
    ]];
    self.bubblePosition=CGPointMake(1,.5);
    id saved=[NSUserDefaults.standardUserDefaults objectForKey:@"FHAssist.overlayPosition.v1"];
    if([saved isKindOfClass:NSDictionary.class] && [saved[@"x"] isKindOfClass:NSNumber.class] && [saved[@"y"] isKindOfClass:NSNumber.class]) {
        double x=[saved[@"x"] doubleValue],y=[saved[@"y"] doubleValue];
        if(std::isfinite(x) && std::isfinite(y)) self.bubblePosition=CGPointMake(std::clamp(x,0.0,1.0),std::clamp(y,0.0,1.0));
    }
    self.bubble=[UIButton buttonWithType:UIButtonTypeSystem];[self.bubble setTitle:@"FH" forState:UIControlStateNormal];
    self.bubble.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    [self.bubble setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.bubble.backgroundColor=[UIColor colorWithWhite:.08 alpha:1];self.bubble.layer.cornerRadius=16;self.bubble.alpha=.55;
    self.bubble.accessibilityLabel=@"展开 FH 设置，可拖动";
    [self.bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBubble:)]];
    [root.view addSubview:self.bubble];
    __weak FHRadarController *weakSelf=self;
    root.onLayout=^{ [weakSelf layoutOverlay]; };
    [self layoutOverlay];
    for(UIButton *b in @[self.button,self.headButton,self.bodyButton,self.zoomButton,self.fireButton]) {
        b.enabled=supported;
        if(!supported) [b setTitle:@"版本不支持" forState:UIControlStateNormal];
    }
    if(supported) [self refresh];else self.report.text=@"FH 0.6 · 游戏版本不支持，未启用";
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
