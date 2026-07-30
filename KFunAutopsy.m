//
//  KfunSolo.m  v5-final
//  参考 KfunHook 原始 dylib 做法：
//  1. Hook activateCode:completion: 用 C 函数（不用 block）
//  2. 不替换 onTapVerify，让原始流程走通
//  3. 拦截 HTTP 请求，直接回调成功
//  4. 原始代码自动: dismiss → ViewController → setupAfterActivation → radarCollectLoop
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

// 构造伪造的服务器响应（和 KfunHook 的 force status=0 一样）
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

#pragma mark - 保存原始 IMP

static IMP g_orig_activateCode = NULL;
static IMP g_orig_verifyWithCompletion = NULL;
static IMP g_orig_checkTask = NULL;
static IMP g_orig_startContinuousAuthCheck = NULL;
static IMP g_orig_onTapVerify = NULL;

#pragma mark - 核心 Hook 函数（C 函数，不用 block）

// ⚡ 这是 KfunHook 的核心做法：
// 用 C 函数替换 activateCode:completion: 的 IMP
// 直接调用 completion 回调成功，不发网络请求
// 原始 onTapVerify 代码会收到成功回调，继续走 dismiss → ViewController → radar
//
// activateCode:completion: 的 type encoding: v32@0:8@16@24
// 即: -(void)activateCode:(NSString *)code completion:(void(^)(BOOL success, id result))completion
static void kf_hooked_activateCode(id self, SEL _cmd, NSString *code, id completion) {
    KS(@"[HOOK] ⭐ activateCode:completion: 拦截! code=%@", code);
    logStack(0, 5);
    injectFakeState();
    
    // completion 是一个 block: void(^)(BOOL success, id result)
    // 直接调用它，传入成功
    if (completion) {
        void (^comp)(BOOL, id) = completion;
        comp(YES, buildFakeServerResponse());
        KS(@"[HOOK]   ✅ completion(YES, fakeResponse) 已调用");
    } else {
        KS(@"[HOOK]   ⚠️ completion 为 nil");
    }
}

// 备用: verifyWithCompletion: hook
// type encoding: v24@0:8@16
// -(void)verifyWithCompletion:(void(^)(BOOL))completion
static void kf_hooked_verifyWithCompletion(id self, SEL _cmd, id completion) {
    KS(@"[HOOK] ⭐ verifyWithCompletion: 拦截!");
    injectFakeState();
    if (completion) {
        void (^comp)(BOOL) = completion;
        comp(YES);
    }
}

// checkTask hook - 阻止后台验证
static void kf_hooked_checkTask(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ checkTask 拦截 — 跳过");
}

// startContinuousAuthCheck hook - 阻止持续验证
static void kf_hooked_startContinuousAuthCheck(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ startContinuousAuthCheck 拦截 — 跳过");
}

// onTapVerify hook - 注入假状态 + 调原始实现
// 这样不管原始 onTapVerify 做什么检查，我们都在前面注入了假状态
static void kf_hooked_onTapVerify(id self, SEL _cmd) {
    KS(@"[HOOK] ⭐ onTapVerify 拦截! 注入假状态后调原始");
    logStack(0, 5);
    injectFakeState();
    
    // 调原始 onTapVerify — 它会走到 activateCode:completion:（已被我们 hook）
    if (g_orig_onTapVerify) {
        ((void (*)(id, SEL))g_orig_onTapVerify)(self, _cmd);
        KS(@"[HOOK]   onTapVerify 原始执行完毕");
    }
}

#pragma mark - Hook 安装工具

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
    KS(@"[SCAN] === 全局扫描 activateCode / onTapVerify ===");
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
                [name isEqualToString:@"verifyWithCompletion:"] ||
                [name isEqualToString:@"checkTask"] ||
                [name isEqualToString:@"radarCollectLoop"] ||
                [name isEqualToString:@"setupAfterActivation"]) {
                KS(@"[SCAN]   %s → %@", class_getName(classes[i]), name);
            }
        }
        free(methods);
    }
    free(classes);
    KS(@"[SCAN] === 扫描完成 ===");
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
        KS(@"策略: 参考 KfunHook 原始做法");
        KS(@"  1. Hook activateCode:completion: (C函数) → 直接回调成功");
        KS(@"  2. Hook onTapVerify → 注入假状态 + 调原始");
        KS(@"  3. 原始流程自动: dismiss → ViewController → radar");
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
        
        // 先全局扫描
        scanAllClasses();
        
        // ====== Hook WWWActivationViewController ======
        Class actVC = objc_getClass("WWWActivationViewController");
        KS(@"[INIT] WWWActivationViewController: %s", actVC ? "✅" : "❌");
        
        if (actVC) {
            // Hook onTapVerify — 注入假状态 + 调原始
            installHook(actVC, @selector(onTapVerify),
                       (IMP)kf_hooked_onTapVerify, &g_orig_onTapVerify, "注入假状态");
            
            // 也 hook activateCode:completion:（以防万一这个类上也有）
            installHook(actVC, @selector(activateCode:completion:),
                       (IMP)kf_hooked_activateCode, NULL, "备用");
        }
        
        // ====== Hook WWWActivation ======
        Class activation = objc_getClass("WWWActivation");
        KS(@"[INIT] WWWActivation: %s", activation ? "✅" : "❌");
        
        if (activation) {
            // ⚡ 核心 hook — 和 KfunHook 一样的做法
            installHook(activation, @selector(activateCode:completion:),
                       (IMP)kf_hooked_activateCode, &g_orig_activateCode, "核心");
            
            installHook(activation, @selector(verifyWithCompletion:),
                       (IMP)kf_hooked_verifyWithCompletion, &g_orig_verifyWithCompletion, "备用");
            
            installHook(activation, @selector(checkTask),
                       (IMP)kf_hooked_checkTask, NULL, "阻止后台验证");
        }
        
        // ====== Hook ViewController ======
        Class mainVC = objc_getClass("ViewController");
        KS(@"[INIT] ViewController: %s", mainVC ? "✅" : "❌");
        
        if (mainVC) {
            installHook(mainVC, @selector(checkTask),
                       (IMP)kf_hooked_checkTask, NULL, "阻止后台验证");
            
            installHook(mainVC, @selector(startContinuousAuthCheck),
                       (IMP)kf_hooked_startContinuousAuthCheck, &g_orig_startContinuousAuthCheck, "阻止持续验证");
        }
        
        // ====== 重试 ======
        if (!actVC || !activation || !mainVC) {
            KS(@"[INIT] 部分类未找到，3秒后重试...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!actVC) {
                    Class r = objc_getClass("WWWActivationViewController");
                    if (r) {
                        KS(@"[INIT] Retry: ✅ WWWActivationViewController");
                        installHook(r, @selector(onTapVerify), (IMP)kf_hooked_onTapVerify, &g_orig_onTapVerify, "retry");
                        installHook(r, @selector(activateCode:completion:), (IMP)kf_hooked_activateCode, NULL, "retry");
                    }
                }
                if (!activation) {
                    Class r = objc_getClass("WWWActivation");
                    if (r) {
                        KS(@"[INIT] Retry: ✅ WWWActivation");
                        installHook(r, @selector(activateCode:completion:), (IMP)kf_hooked_activateCode, &g_orig_activateCode, "retry");
                        installHook(r, @selector(verifyWithCompletion:), (IMP)kf_hooked_verifyWithCompletion, &g_orig_verifyWithCompletion, "retry");
                    }
                }
                if (!mainVC) {
                    Class r = objc_getClass("ViewController");
                    if (r) {
                        KS(@"[INIT] Retry: ✅ ViewController");
                        installHook(r, @selector(checkTask), (IMP)kf_hooked_checkTask, NULL, "retry");
                        installHook(r, @selector(startContinuousAuthCheck), (IMP)kf_hooked_startContinuousAuthCheck, &g_orig_startContinuousAuthCheck, "retry");
                    }
                }
                scanAllClasses();
            });
        }
        
        KS(@"[INIT] ✅ 所有 Hook 安装完成");
        KS(@"[INIT] 现在请输入任意卡密，点击验证...");
    });
}

#pragma clang diagnostic pop
