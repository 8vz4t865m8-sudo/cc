//
//  KfunSolo.m  v5-final
//  核心策略：
//  1. hook onTapVerify → 完全替换，不调原始（绕过15位校验+网络请求）
//  2. hook activateCode:completion: → C函数直接回调成功
//  3. 手动 dismiss + 触发 ViewController 初始化
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import <execinfo.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma mark - 日志引擎

@interface KSLogger : NSObject
+ (instancetype)shared;
- (void)log:(NSString *)fmt, ...;
- (NSString *)allText;
- (void)clear;
@property (nonatomic, strong) NSMutableString *buffer;
@property (nonatomic, strong) NSDateFormatter *timeFmt;
@end

@implementation KSLogger
+ (instancetype)shared {
    static KSLogger *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}
- (instancetype)init {
    self = [super init];
    _buffer = [NSMutableString string];
    _timeFmt = [[NSDateFormatter alloc] init];
    _timeFmt.dateFormat = @"HH:mm:ss.SSS";
    return self;
}
- (void)log:(NSString *)fmt, ... {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *ts = [_timeFmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
    [_buffer appendString:line];
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [[docs firstObject] stringByAppendingPathComponent:@"kfun_solo.log"];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    else { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"KSLogAppend" object:line];
}
- (NSString *)allText { return [_buffer copy]; }
- (void)clear { [_buffer setString:@""]; }
@end

#define KS(fmt, ...) [[KSLogger shared] log:fmt, ##__VA_ARGS__]

#pragma mark - 悬浮窗

@interface KSWindow : UIWindow
@property (nonatomic, strong) UITextView *console;
@end

@implementation KSWindow
- (instancetype)init {
    CGRect sr = [UIScreen mainScreen].bounds;
    CGFloat W = sr.size.width * 0.88, H = sr.size.height * 0.50;
    self = [super initWithFrame:CGRectMake((sr.size.width-W)/2, 60, W, H)];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 200;
        self.backgroundColor = [UIColor colorWithWhite:0.03 alpha:0.94];
        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0].CGColor;
        self.hidden = NO;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)scene).activationState == UISceneActivationStateForegroundActive) {
                    self.windowScene = (UIWindowScene *)scene; break;
                }
            }
        }
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 34)];
        bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
        [self addSubview:bar];
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, W-140, 26)];
        t.text = @"🚀 KfunSolo v5"; t.font = [UIFont boldSystemFontOfSize:12];
        t.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.5 alpha:1.0];
        [bar addSubview:t];
        UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
        cp.frame = CGRectMake(W-130, 2, 60, 30);
        [cp setTitle:@"📋复制" forState:UIControlStateNormal];
        cp.titleLabel.font = [UIFont systemFontOfSize:11];
        [cp setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
        [cp addTarget:self action:@selector(copyAll) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:cp];
        UIButton *cl = [UIButton buttonWithType:UIButtonTypeSystem];
        cl.frame = CGRectMake(W-65, 2, 60, 30);
        [cl setTitle:@"🗑清空" forState:UIControlStateNormal];
        cl.titleLabel.font = [UIFont systemFontOfSize:11];
        [cl setTitleColor:[UIColor orangeColor] forState:UIControlStateNormal];
        [cl addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:cl];
        _console = [[UITextView alloc] initWithFrame:CGRectMake(3, 38, W-6, H-42)];
        _console.backgroundColor = [UIColor clearColor];
        _console.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.4 alpha:1.0];
        _console.font = [UIFont fontWithName:@"Courier" size:9];
        _console.editable = NO; _console.selectable = YES;
        [self addSubview:_console];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [bar addGestureRecognizer:pan];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onLine:) name:@"KSLogAppend" object:nil];
    }
    return self;
}
- (void)onLine:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = n.object;
        self.console.text = [NSString stringWithFormat:@"%@%@", self.console.text, line];
        [self.console scrollRangeToVisible:NSMakeRange(self.console.text.length-1, 1)];
    });
}
- (void)copyAll { UIPasteboard.generalPasteboard.string = [KSLogger shared].allText; KS(@"[SYS] 已复制"); }
- (void)clearAll { [[KSLogger shared] clear]; self.console.text = @""; KS(@"=== 已清空 ==="); }
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x+t.x, self.center.y+t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}
@end

static KSWindow *g_win = nil;

#pragma mark - 崩溃捕获

static void ks_crash_handler(int sig, siginfo_t *info, void *ctx) {
    KS(@"[CRASH] ⚠️ 信号: sig=%d addr=%p", sig, info->si_addr);
    void *frames[32]; int n = backtrace(frames, 32);
    char **syms = backtrace_symbols(frames, n);
    for (int i = 0; i < n; i++) KS(@"  ↳ [%d] %s", i, syms[i]);
    free(syms); signal(sig, SIG_DFL); raise(sig);
}

static void ks_exception_handler(NSException *e) {
    KS(@"[CRASH] ⚠️ 异常: %@", e.name);
    KS(@"[CRASH] Reason: %@", e.reason);
    KS(@"[CRASH] Stack: %@", [e callStackSymbols]);
}

#pragma mark - 辅助

static void logStack(int skip, int max) {
    NSArray *syms = [NSThread callStackSymbols];
    for (int i = skip+2; i < MIN((int)syms.count, skip+2+max); i++) KS(@"  ↳ %@", syms[i]);
}

static void injectFakeState(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:@"DP5372QRM1NK3L7" forKey:@"xTcAwvyFDr9CujLx"];
    [ud setBool:YES forKey:@"kfun_activated"];
    [ud setObject:@"2099-12-31T23:59:59Z" forKey:@"expire_date"];
    [ud setObject:@"951951" forKey:@"appid"];
    [ud synchronize];
    KS(@"[FAKE] 已注入伪造验证状态");
}

static NSDictionary *buildFakeServerResponse(void) {
    return @{
        @"success": @YES,
        @"message": @"激活成功",
        @"data": @{
            @"expires_at": @"2099-12-31T23:59:59Z",
            @"expire": @"2099-12-31T23:59:59Z",
            @"endtime": @"2099-12-31 23:59:59",
            @"time": @"2099-12-31 23:59:59",
            @"vip_time": @"2099-12-31 23:59:59",
            @"status": @"active",
            @"appid": @"951951",
            @"action": @"activate"
        },
        @"status": @"success"
    };
}

#pragma mark - 前向声明

static void ks_initMainVC(void);

#pragma mark - 保存原始 IMP

static IMP g_orig_activateCode = NULL;
static IMP g_orig_onTapVerify = NULL;
static IMP g_orig_startContinuousAuthCheck = NULL;

#pragma mark - Hook: activateCode:completion: (核心)

// type encoding: v32@0:8@16@24
static void kf_hooked_activateCode(id self, SEL _cmd, NSString *code, id completion) {
    KS(@"[HOOK] ⭐ activateCode:completion: 拦截! code=%@", code);
    logStack(0, 5);
    injectFakeState();
    
    if (completion) {
        void (^comp)(BOOL, id) = completion;
        NSDictionary *resp = buildFakeServerResponse();
        KS(@"[HOOK]   即将异步回调 completion(YES)");
        dispatch_async(dispatch_get_main_queue(), ^{
            comp(YES, resp);
            KS(@"[HOOK]   ✅ completion(YES, fakeResponse) 已调用");
        });
    } else {
        KS(@"[HOOK]   ⚠️ completion 为 nil");
    }
}

#pragma mark - Hook: onTapVerify (完全替换)

// ⚡ 完全替换 onTapVerify，不调原始
// 原始 onTapVerify 有15位校验 + 网络请求，会导致闪退
// 我们直接: 注入假状态 → dismiss → 找 ViewController → 初始化
static void kf_hooked_onTapVerify(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ onTapVerify 拦截! 完全替换");
    logStack(0, 5);
    injectFakeState();
    
    // 不调原始 onTapVerify！
    // 直接手动走后续流程
    
    UIViewController *actVC = (UIViewController *)self;
    
    // 1. 隐藏验证UI
    @try {
        UIView *mask = [actVC valueForKey:@"authMaskView"];
        if (mask) { mask.hidden = YES; [mask removeFromSuperview]; KS(@"[INIT]   authMaskView 已移除"); }
    } @catch (NSException *e) {}
    
    @try {
        UIActivityIndicatorView *spinner = [actVC valueForKey:@"spinner"];
        if (spinner) { [spinner stopAnimating]; spinner.hidden = YES; }
    } @catch (NSException *e) {}
    
    // 2. 异步 dismiss + 初始化主页
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        KS(@"[INIT]   开始 dismiss...");
        if (actVC.presentingViewController) {
            [actVC dismissViewControllerAnimated:YES completion:^{
                KS(@"[INIT]   ✅ dismiss 完成，开始初始化主页");
                ks_initMainVC();
            }];
        } else {
            KS(@"[INIT]   ⚠️ 无 presentingViewController，直接初始化");
            ks_initMainVC();
        }
    });
}

#pragma mark - 追踪 Hook

static IMP g_orig_radarCollectLoop = NULL;
static IMP g_orig_radarPushLoop = NULL;
static IMP g_orig_readLoop = NULL;
static IMP g_orig_setup = NULL;

// radarCollectLoop hook - 追踪
static void kf_hooked_radarCollectLoop(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ radarCollectLoop START");
    logStack(0, 5);
    if (g_orig_radarCollectLoop) {
        ((void (*)(id, SEL))g_orig_radarCollectLoop)(self, _cmd);
        KS(@"[HOOK]   radarCollectLoop 原始执行完毕");
    }
}

// radarPushLoop hook - 追踪
static void kf_hooked_radarPushLoop(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ radarPushLoop START");
    if (g_orig_radarPushLoop) {
        ((void (*)(id, SEL))g_orig_radarPushLoop)(self, _cmd);
        KS(@"[HOOK]   radarPushLoop 原始执行完毕");
    }
}

// readLoop hook - 追踪
static void kf_hooked_readLoop(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ readLoop START");
    if (g_orig_readLoop) {
        ((void (*)(id, SEL))g_orig_readLoop)(self, _cmd);
        KS(@"[HOOK]   readLoop 原始执行完毕");
    }
}

// setup hook - 追踪
static void kf_hooked_setup(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ setup START");
    logStack(0, 5);
    if (g_orig_setup) {
        ((void (*)(id, SEL))g_orig_setup)(self, _cmd);
        KS(@"[HOOK]   setup 原始执行完毕");
    }
}

static void kf_hooked_checkTask(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ checkTask 拦截 — 跳过");
}

static void kf_hooked_startContinuousAuthCheck(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ startContinuousAuthCheck 拦截 — 跳过");
}

#pragma mark - 主页初始化

static void ks_initMainVC(void) {
    Class mainClass = objc_getClass("ViewController");
    if (!mainClass) {
        KS(@"[INIT]   ❌ ViewController 类不存在");
        return;
    }
    
    // 在所有 window 中找 ViewController
    __block id mainVC = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *root = window.rootViewController;
        if ([root isKindOfClass:mainClass]) { mainVC = root; break; }
        if ([root isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)root;
            for (UIViewController *vc in nav.viewControllers) {
                if ([vc isKindOfClass:mainClass]) { mainVC = vc; break; }
            }
            if (!mainVC && [nav.topViewController isKindOfClass:mainClass]) mainVC = nav.topViewController;
        }
        if ([root isKindOfClass:[UITabBarController class]]) {
            UITabBarController *tab = (UITabBarController *)root;
            for (UIViewController *vc in tab.viewControllers) {
                if ([vc isKindOfClass:mainClass]) { mainVC = vc; break; }
                if ([vc isKindOfClass:[UINavigationController class]]) {
                    UINavigationController *nav = (UINavigationController *)vc;
                    for (UIViewController *nvc in nav.viewControllers) {
                        if ([nvc isKindOfClass:mainClass]) { mainVC = nvc; break; }
                    }
                }
            }
        }
    }
    
    // 也检查 presentedViewController
    if (!mainVC) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            UIViewController *top = window.rootViewController;
            while (top.presentedViewController) {
                top = top.presentedViewController;
                if ([top isKindOfClass:mainClass]) { mainVC = top; break; }
            }
            if (mainVC) break;
        }
    }
    
    if (!mainVC) {
        KS(@"[INIT]   ❌ 未找到 ViewController，1秒后重试...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ks_initMainVC();
        });
        return;
    }
    
    KS(@"[INIT]   ✅ 找到主页: %@", mainVC);
    
    // ⚡ 按正确顺序调用初始化链
    // 正常流程: viewDidLoad → setup → setupAfterActivation → radarCollectLoop → radarPushLoop
    
    // 1. viewDidLoad
    @try {
        if ([mainVC respondsToSelector:@selector(viewDidLoad)]) {
            [mainVC performSelector:@selector(viewDidLoad)];
            KS(@"[INIT]   ✅ viewDidLoad 已调用");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ viewDidLoad 异常: %@", e.reason); }
    
    // 2. setup
    @try {
        if ([mainVC respondsToSelector:@selector(setup)]) {
            [mainVC performSelector:@selector(setup)];
            KS(@"[INIT]   ✅ setup 已调用");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ setup 异常: %@", e.reason); }
    
    // 3. setupAfterActivation
    @try {
        if ([mainVC respondsToSelector:@selector(setupAfterActivation)]) {
            [mainVC performSelector:@selector(setupAfterActivation)];
            KS(@"[INIT]   ✅ setupAfterActivation 已调用");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ setupAfterActivation 异常: %@", e.reason); }
    
    // 调用 setupBackgroundKeepAlive
    @try {
        if ([mainVC respondsToSelector:@selector(setupBackgroundKeepAlive)]) {
            [mainVC performSelector:@selector(setupBackgroundKeepAlive)];
            KS(@"[INIT]   ✅ setupBackgroundKeepAlive 已调用");
        }
    } @catch (NSException *e) {}
    
    // 调用 radarCollectLoop（收集数据）
    @try {
        if ([mainVC respondsToSelector:@selector(radarCollectLoop)]) {
            [mainVC performSelector:@selector(radarCollectLoop)];
            KS(@"[INIT]   ✅ radarCollectLoop 已调用");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ radarCollectLoop 异常: %@", e.reason); }
    
    // 调用 radarPushLoop（推送数据到前端）
    @try {
        if ([mainVC respondsToSelector:@selector(radarPushLoop)]) {
            [mainVC performSelector:@selector(radarPushLoop)];
            KS(@"[INIT]   ✅ radarPushLoop 已调用");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ radarPushLoop 异常: %@", e.reason); }
    
    // 调用 readLoop（读取循环）
    @try {
        if ([mainVC respondsToSelector:@selector(readLoop)]) {
            [mainVC performSelector:@selector(readLoop)];
            KS(@"[INIT]   ✅ readLoop 已调用");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ readLoop 异常: %@", e.reason); }
    
    // 刷新 tableView
    @try {
        id tv = [mainVC valueForKey:@"tableView"];
        if (tv && [tv isKindOfClass:[UITableView class]]) {
            [(UITableView *)tv reloadData];
            KS(@"[INIT]   ✅ tableView reloadData");
        }
    } @catch (NSException *e) {}
    
    // 隐藏 authMaskView（如果主页也有）
    @try {
        UIView *mask = [mainVC valueForKey:@"authMaskView"];
        if (mask) { mask.hidden = YES; [mask removeFromSuperview]; KS(@"[INIT]   主页 authMaskView 已移除"); }
    } @catch (NSException *e) {}
    
    KS(@"[INIT]   ✅ 主页初始化完成");
}

#pragma mark - Hook 安装

static void installHook(Class cls, SEL sel, IMP newImp, IMP *origOut, const char *label) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        KS(@"[HOOK] ❌ %s.%s not found (%s)", class_getName(cls), sel_getName(sel), label);
        return;
    }
    IMP current = method_getImplementation(m);
    if (origOut) *origOut = current;
    method_setImplementation(m, newImp);
    KS(@"[HOOK] ✅ %s.%s hooked (%s) origIMP=%p", class_getName(cls), sel_getName(sel), label, current);
}

#pragma mark - 全局扫描

static void scanAllClasses(void) {
    KS(@"[SCAN] === 全局扫描 ===");
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    objc_getClassList(classes, numClasses);
    for (int i = 0; i < numClasses; i++) {
        unsigned int mc = 0;
        Method *methods = class_copyMethodList(classes[i], &mc);
        if (!methods) continue;
        for (unsigned int j = 0; j < mc; j++) {
            NSString *name = NSStringFromSelector(method_getName(methods[j]));
            if ([name isEqualToString:@"activateCode:completion:"] ||
                [name isEqualToString:@"onTapVerify"] ||
                [name isEqualToString:@"checkTask"] ||
                [name isEqualToString:@"radarCollectLoop"] ||
                [name isEqualToString:@"setupAfterActivation"] ||
                [name isEqualToString:@"startContinuousAuthCheck"] ||
                [name isEqualToString:@"onVerify"]) {
                KS(@"[SCAN]   %s → %@", class_getName(classes[i]), name);
            }
        }
        free(methods);
    }
    free(classes);
    KS(@"[SCAN] === 完成 ===");
}

#pragma mark - 构造函数

__attribute__((constructor))
static void ks_init(void) {
    NSLog(@"========================================");
    NSLog(@"[KfunSolo] v5 - Final");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_win = [[KSWindow alloc] init];
        
        KS(@"=== KfunSolo v5-final 启动 ===");
        KS(@"策略: 完全替换 onTapVerify + hook activateCode");
        KS(@"");
        
        // 崩溃捕获
        struct sigaction sa;
        sa.sa_sigaction = ks_crash_handler;
        sa.sa_flags = SA_SIGINFO;
        sigemptyset(&sa.sa_mask);
        sigaction(SIGSEGV, &sa, NULL);
        sigaction(SIGBUS, &sa, NULL);
        sigaction(SIGILL, &sa, NULL);
        sigaction(SIGABRT, &sa, NULL);
        NSSetUncaughtExceptionHandler(ks_exception_handler);
        KS(@"[INIT] 崩溃捕获已启用");
        
        scanAllClasses();
        
        // Hook WWWActivationViewController
        Class actVC = objc_getClass("WWWActivationViewController");
        KS(@"[INIT] WWWActivationViewController: %s", actVC ? "✅" : "❌");
        if (actVC) {
            installHook(actVC, @selector(onTapVerify), (IMP)kf_hooked_onTapVerify, &g_orig_onTapVerify, "完全替换");
            installHook(actVC, @selector(activateCode:completion:), (IMP)kf_hooked_activateCode, NULL, "备用");
            installHook(actVC, @selector(checkTask), (IMP)kf_hooked_checkTask, NULL, "防验证");
        }
        
        // Hook WWWActivation
        Class activation = objc_getClass("WWWActivation");
        KS(@"[INIT] WWWActivation: %s", activation ? "✅" : "❌");
        if (activation) {
            installHook(activation, @selector(activateCode:completion:), (IMP)kf_hooked_activateCode, &g_orig_activateCode, "核心");
        }
        
        // Hook ViewController
        Class mainVC = objc_getClass("ViewController");
        KS(@"[INIT] ViewController: %s", mainVC ? "✅" : "❌");
        if (mainVC) {
            installHook(mainVC, @selector(checkTask), (IMP)kf_hooked_checkTask, NULL, "防验证");
            installHook(mainVC, @selector(startContinuousAuthCheck), (IMP)kf_hooked_startContinuousAuthCheck, &g_orig_startContinuousAuthCheck, "防验证");
            // 追踪数据层方法
            installHook(mainVC, @selector(setup), (IMP)kf_hooked_setup, &g_orig_setup, "追踪");
            installHook(mainVC, @selector(radarCollectLoop), (IMP)kf_hooked_radarCollectLoop, &g_orig_radarCollectLoop, "追踪");
            installHook(mainVC, @selector(radarPushLoop), (IMP)kf_hooked_radarPushLoop, &g_orig_radarPushLoop, "追踪");
            installHook(mainVC, @selector(readLoop), (IMP)kf_hooked_readLoop, &g_orig_readLoop, "追踪");
        }
        
        KS(@"[INIT] ✅ Hook 安装完成，点击验证即可...");
    });
}

#pragma clang diagnostic pop
