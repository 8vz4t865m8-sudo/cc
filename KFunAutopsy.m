//
//  KfunSolo.m  v3-fix
//  修正：hook activateCode:completion: 而不是 onTapVerify
//  让原始 onTapVerify 流程走通，自动 dismiss → 展示 ViewController → 初始化雷达
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
        t.text = @"🚀 KfunSolo v3"; t.font = [UIFont boldSystemFontOfSize:12];
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

#pragma mark - 伪造验证数据

static NSDictionary *buildFakeResponse(void) {
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

static void injectFakeState(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:@"DP5372QRM1NK3L7" forKey:@"xTcAwvyFDr9CujLx"];
    [ud setBool:YES forKey:@"kfun_activated"];
    [ud setObject:@"2099-12-31T23:59:59Z" forKey:@"expire_date"];
    [ud setObject:@"951951" forKey:@"appid"];
    [ud synchronize];
    KS(@"[FAKE] 已注入伪造验证状态");
}

#pragma mark - Hook 入口 — 核心改动

// ✅ Hook activateCode:completion: 而不是 onTapVerify
// 让 onTapVerify 原始代码正常执行，它内部会调用 activateCode:completion:
// 我们拦截这个方法，直接回调成功，原始流程就会继续走：dismiss → 展示主页 → 初始化雷达
static void hookActivateCode(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (!m) { KS(@"[HOOK] ❌ activateCode:completion: not found"); return; }
    KS(@"[HOOK] ✅ activateCode:completion:");
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^(id self, id code, void (^completion)(BOOL success, id result)) {
        KS(@"[ACT] ⭐ activateCode 拦截 — code=%@", code);
        logStack(0, 3);
        injectFakeState();
        // 直接回调成功，让 onTapVerify 的原始流程继续执行
        if (completion) {
            completion(YES, buildFakeResponse());
            KS(@"[ACT]   ✅ 已回调 success=YES，原始流程将继续");
        }
    });
    method_setImplementation(m, newIMP);
}

// ✅ 也 hook verifyWithCompletion: 作为备用
// 有些版本可能不走 activateCode 而走 verifyWithCompletion
static void hookVerifyWithCompletion(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(verifyWithCompletion:));
    if (!m) { KS(@"[HOOK] ⚠️ verifyWithCompletion: not found"); return; }
    KS(@"[HOOK] ✅ verifyWithCompletion:");
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^(id self, void (^completion)(BOOL)) {
        KS(@"[ACT] ⭐ verifyWithCompletion 拦截");
        injectFakeState();
        if (completion) completion(YES);
    });
    method_setImplementation(m, newIMP);
}

// ✅ Hook checkTask — 防止后台定时验证失败导致退出
static void hookCheckTask(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(checkTask));
    if (!m) { KS(@"[HOOK] ⚠️ checkTask not found"); return; }
    KS(@"[HOOK] ✅ checkTask");
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^void(id self) {
        KS(@"[AUTH] ⭐ checkTask 拦截 — 跳过验证检查");
        // 不调用原始实现，直接返回，防止验证失败
    });
    method_setImplementation(m, newIMP);
}

// ✅ Hook startContinuousAuthCheck — 防止持续验证失败
static void hookStartContinuousAuthCheck(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(startContinuousAuthCheck));
    if (!m) { KS(@"[HOOK] ⚠️ startContinuousAuthCheck not found"); return; }
    KS(@"[HOOK] ✅ startContinuousAuthCheck in %s", class_getName(cls));
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^void(id self) {
        KS(@"[AUTH] ⭐ startContinuousAuthCheck 拦截 — 跳过持续验证");
        // 不调用原始实现，防止持续验证失败导致退出
    });
    method_setImplementation(m, newIMP);
}

// ✅ Hook setupAfterActivation — 仅用于日志，调用原始实现
static void hookSetupAfterActivation(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(setupAfterActivation));
    if (!m) return;
    KS(@"[HOOK] ✅ setupAfterActivation in %s", class_getName(cls));
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^void(id self) {
        KS(@"[MAIN] ⭐ setupAfterActivation START (class=%s)", class_getName([self class]));
        logStack(0, 6);
        // 调用原始实现！这是初始化雷达的关键
        ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
        KS(@"[MAIN]   ✅ setupAfterActivation END");
    });
    method_setImplementation(m, newIMP);
}

#pragma mark - 自动扫描验证方法（仅日志）

static void scanAndLogMethods(Class cls) {
    KS(@"[SCAN] 扫描 %s 的方法...", class_getName(cls));
    unsigned int mc = 0;
    Method *methods = class_copyMethodList(cls, &mc);
    int found = 0;
    for (unsigned int i = 0; i < mc; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        NSString *lower = [name lowercaseString];
        if ([lower containsString:@"verify"] || [lower containsString:@"check"] || 
            [lower containsString:@"auth"] || [lower containsString:@"activ"] || 
            [lower containsString:@"code"] || [lower containsString:@"setup"] ||
            [lower containsString:@"radar"] || [lower containsString:@"loop"]) {
            KS(@"[SCAN]   %@", name);
            found++;
        }
    }
    if (methods) free(methods);
    KS(@"[SCAN]   发现 %d 个相关方法", found);
}

#pragma mark - 构造函数

__attribute__((constructor))
static void ks_init(void) {
    NSLog(@"========================================");
    NSLog(@"[KfunSolo] v3 - Fixed Bypass");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_win = [[KSWindow alloc] init];
        
        KS(@"=== KfunSolo v3 启动 ===");
        KS(@"修正：hook activateCode:completion: 而不是 onTapVerify");
        KS(@"让原始流程走通: onTapVerify → activateCode → dismiss → ViewController → radarCollectLoop");
        KS(@"");
        
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
        
        // === Hook WWWActivationViewController ===
        Class actVC = objc_getClass("WWWActivationViewController");
        if (actVC) {
            KS(@"[INIT] ✅ 找到 WWWActivationViewController");
            
            // ⚡ 核心：hook activateCode:completion: — 拦截验证请求，直接返回成功
            hookActivateCode(actVC);
            
            // 备用：hook verifyWithCompletion: — 部分版本可能走这个路径
            hookVerifyWithCompletion(actVC);
            
            // 仅日志：hook showSuccess 和 setupAfterActivation 用于追踪流程
            hookSetupAfterActivation(actVC);
            
            // hook checkTask — 防止后台定时验证失败
            hookCheckTask(actVC);
            
            // hook startContinuousAuthCheck — 防止持续验证失败
            hookStartContinuousAuthCheck(actVC);
            
            // 扫描并记录所有验证相关方法
            scanAndLogMethods(actVC);
            
        } else {
            KS(@"[INIT] ❌ WWWActivationViewController not found!");
        }
        
        // === Hook ViewController ===
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) {
            KS(@"[INIT] ✅ 找到 ViewController");
            
            // hook setupAfterActivation — 仅日志追踪，调用原始实现
            hookSetupAfterActivation(mainVC);
            
            // hook checkTask — 防止后台定时验证失败
            hookCheckTask(mainVC);
            
            // hook startContinuousAuthCheck — 防止持续验证失败
            hookStartContinuousAuthCheck(mainVC);
            
            scanAndLogMethods(mainVC);
            
        } else {
            KS(@"[INIT] ❌ ViewController not found!");
        }
        
        // === 重试机制 ===
        if (!actVC || !mainVC) {
            KS(@"[INIT] 等待 3 秒重试...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!actVC) {
                    Class retry = objc_getClass("WWWActivationViewController");
                    if (retry) {
                        KS(@"[INIT] Retry: ✅ WWWActivationViewController");
                        hookActivateCode(retry);
                        hookVerifyWithCompletion(retry);
                        hookSetupAfterActivation(retry);
                        hookCheckTask(retry);
                        hookStartContinuousAuthCheck(retry);
                        scanAndLogMethods(retry);
                    } else {
                        KS(@"[INIT] Retry: ❌ WWWActivationViewController still not found");
                    }
                }
                if (!mainVC) {
                    Class retry = objc_getClass("ViewController");
                    if (retry) {
                        KS(@"[INIT] Retry: ✅ ViewController");
                        hookSetupAfterActivation(retry);
                        hookCheckTask(retry);
                        hookStartContinuousAuthCheck(retry);
                        scanAndLogMethods(retry);
                    } else {
                        KS(@"[INIT] Retry: ❌ ViewController still not found");
                    }
                }
            });
        }
        
        KS(@"[INIT] ✅ Hook 安装完成，等待用户点击验证...");
    });
}

#pragma clang diagnostic pop
