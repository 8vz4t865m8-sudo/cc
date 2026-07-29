//
//  KfunSolo.m  v2
//  修正：NSString 参数 + 自动发现验证方法 + 修复 dismiss 逻辑
//  编译命令不变
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import <execinfo.h>

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
        t.text = @"🚀 KfunSolo v2"; t.font = [UIFont boldSystemFontOfSize:12];
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

static void dumpDict(id obj, int depth) {
    if (!obj || ![obj isKindOfClass:[NSDictionary class]]) {
        KS(@"%@⚠️ 非字典: %@ (%@)", [@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0], obj, NSStringFromClass([obj class]));
        return;
    }
    for (id k in (NSDictionary *)obj) {
        id v = ((NSDictionary *)obj)[k];
        NSString *ind = [@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0];
        if ([v isKindOfClass:[NSDictionary class]]) {
            KS(@"%@\"%@\" → {", ind, k);
            dumpDict(v, depth+1);
            KS(@"%@}", ind);
        } else if ([v isKindOfClass:[NSArray class]]) {
            KS(@"%@\"%@\" → [%lu]", ind, k, (unsigned long)[(NSArray *)v count]);
            for (id item in (NSArray *)v) KS(@"%@  · %@", ind, item);
        } else {
            NSString *d = [v description];
            if (d.length > 120) d = [d substringToIndex:120];
            KS(@"%@\"%@\" = \"%@\" [%@]", ind, k, d, NSStringFromClass([v class]));
        }
    }
}

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

#pragma mark - 补全初始化链

static void ks_postDismissInit(void);
static void ks_initXPF(void);

static void runFullInitChain(id activationVC) {
    KS(@"[INIT] ⭐ 开始补全初始化链");
    
    @try {
        id spinner = [activationVC valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
            KS(@"[INIT]   spinner 已停止");
        }
    } @catch (NSException *e) {}
    
    @try {
        id err = [activationVC valueForKey:@"errorLabel"];
        if (err && [err isKindOfClass:[UIView class]]) [(UIView *)err setHidden:YES];
    } @catch (NSException *e) {}
    
    @try {
        id mask = [activationVC valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            KS(@"[INIT]   authMaskView 已移除");
        }
    } @catch (NSException *e) {}
    
    // ⭐ 修正：传入 NSString 而不是 NSDate
    @try {
        if ([activationVC respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            NSString *expireStr = @"2099-12-31 23:59:59";
            [activationVC performSelector:@selector(buildSuccessViewWithExpire:) withObject:expireStr];
            KS(@"[INIT]   buildSuccessViewWithExpire: 已调用 (NSString: %@)", expireStr);
        }
    } @catch (NSException *e) { KS(@"[INIT]   buildSuccessViewWithExpire: 异常: %@", e.reason); }
    
    @try {
        if ([activationVC respondsToSelector:@selector(showSuccess:completion:)]) {
            void (^comp)(void) = ^{
                KS(@"[INIT]   showSuccess completion 执行");
            };
            [activationVC performSelector:@selector(showSuccess:completion:) withObject:@"到期时间:2099-12-31 23:59:59" withObject:comp];
            KS(@"[INIT]   showSuccess:completion: 已调用");
        }
    } @catch (NSException *e) { KS(@"[INIT]   showSuccess:completion: 异常: %@", e.reason); }
    
    // ⭐ 修正：不手动 dismiss，让原版自己处理
    // 改为延迟执行后续初始化，给原版时间自己切换页面
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        KS(@"[INIT]   延迟初始化开始...");
        ks_postDismissInit();
    });
}

static id ks_findMainVC(void) {
    Class mainClass = objc_getClass("ViewController");
    if (!mainClass) return nil;
    
    // 方法 1: 直接 rootViewController
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *root = window.rootViewController;
        if ([root isKindOfClass:mainClass]) return root;
        
        // 方法 2: UINavigationController
        if ([root isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)root;
            for (UIViewController *vc in nav.viewControllers) {
                if ([vc isKindOfClass:mainClass]) return vc;
            }
            if ([nav.topViewController isKindOfClass:mainClass]) return nav.topViewController;
        }
        
        // 方法 3: UITabBarController
        if ([root isKindOfClass:[UITabBarController class]]) {
            UITabBarController *tab = (UITabBarController *)root;
            for (UIViewController *vc in tab.viewControllers) {
                if ([vc isKindOfClass:mainClass]) return vc;
                if ([vc isKindOfClass:[UINavigationController class]]) {
                    UINavigationController *nav = (UINavigationController *)vc;
                    for (UIViewController *nvc in nav.viewControllers) {
                        if ([nvc isKindOfClass:mainClass]) return nvc;
                    }
                }
            }
        }
    }
    
    // 方法 4: 遍历所有 presentedViewController
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) {
            top = top.presentedViewController;
            if ([top isKindOfClass:mainClass]) return top;
            if ([top isKindOfClass:[UINavigationController class]]) {
                UINavigationController *nav = (UINavigationController *)top;
                for (UIViewController *vc in nav.viewControllers) {
                    if ([vc isKindOfClass:mainClass]) return vc;
                }
            }
        }
    }
    
    return nil;
}

static void ks_postDismissInit(void) {
    id mainVC = ks_findMainVC();
    
    if (!mainVC) {
        KS(@"[INIT]   ❌ 未找到主页 ViewController，1秒后重试...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id retry = ks_findMainVC();
            if (retry) {
                KS(@"[INIT]   重试找到主页: %@", retry);
                [self _ks_initMainVC:retry];
            } else {
                KS(@"[INIT]   ❌ 重试仍未找到主页");
            }
        });
        return;
    }
    
    KS(@"[INIT]   找到主页: %@", mainVC);
    [self _ks_initMainVC:mainVC];
}

// 使用 performSelector 避免编译器警告
+ (void)_ks_initMainVC:(id)mainVC {
    @try {
        if ([mainVC respondsToSelector:@selector(setupAfterActivation)]) {
            [mainVC performSelector:@selector(setupAfterActivation)];
            KS(@"[INIT]   ✅ setupAfterActivation 已调用");
        } else {
            KS(@"[INIT]   ⚠️ setupAfterActivation 不存在");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ setupAfterActivation 异常: %@", e.reason); }
    
    @try {
        if ([mainVC respondsToSelector:@selector(setupBackgroundKeepAlive)]) {
            [mainVC performSelector:@selector(setupBackgroundKeepAlive)];
            KS(@"[INIT]   ✅ setupBackgroundKeepAlive 已调用");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ setupBackgroundKeepAlive 异常: %@", e.reason); }
    
    @try {
        if ([mainVC respondsToSelector:@selector(startContinuousAuthCheck)]) {
            [mainVC performSelector:@selector(startContinuousAuthCheck)];
            KS(@"[INIT]   ✅ startContinuousAuthCheck 已调用");
        } else {
            KS(@"[INIT]   ⚠️ startContinuousAuthCheck 不存在于主页");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ startContinuousAuthCheck 异常: %@", e.reason); }
    
    @try {
        id tv = [mainVC valueForKey:@"tableView"];
        if (tv && [tv isKindOfClass:[UITableView class]]) {
            [(UITableView *)tv reloadData];
            KS(@"[INIT]   ✅ tableView reloadData");
        }
    } @catch (NSException *e) { KS(@"[INIT]   ❌ tableView 刷新异常: %@", e.reason); }
    
    ks_initXPF();
}

static void ks_initXPF(void) {
    KS(@"[XPF] 尝试初始化...");
    unsigned int count = _dyld_image_count();
    void *handle = NULL;
    for (unsigned int i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "libxpf.dylib")) {
            handle = dlopen(name, RTLD_NOLOAD);
            KS(@"[XPF] libxpf found: %s handle=%p", name, handle);
            break;
        }
    }
    if (!handle) { KS(@"[XPF] ❌ libxpf not loaded"); return; }
    
    const char *syms[] = {
        "init", "start", "run", "open", "setup", "config",
        "xpf_init", "xpf_start", "xpf_run", "xpf_open", "xpf_setup",
        "xpf_find_cpu_ttep", "xpf_find_allproc", "xpf_find_arm_vm_init",
        "xpf_find_kern_version", "xpf_find_pmap_enter_options",
        "xpf_find_ptov_table", "xpf_find_vm_first_phys", "xpf_find_vm_last_phys",
        "xpf_find_physmap_base", "xpf_find_kernel_slide", "xpf_find_gPhysBase",
        "xpf_find_gPhysSize", "xpf_find_gVirtBase",
        NULL
    };
    int found = 0;
    for (int i = 0; syms[i]; i++) {
        void *addr = dlsym(handle, syms[i]);
        if (addr) {
            KS(@"[XPF]   dlsym(%s) = %p", syms[i], addr);
            found++;
        }
    }
    if (found == 0) KS(@"[XPF]   所有符号均未找到（已被 strip）");
    
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses > 0) {
        Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
        objc_getClassList(classes, numClasses);
        for (int i = 0; i < numClasses; i++) {
            const char *name = class_getName(classes[i]);
            if (strstr(name, "xpf") || strstr(name, "XPF") || strstr(name, "kfd") || strstr(name, "KFD")) {
                KS(@"[XPF]   发现相关类: %s", name);
                unsigned int mc = 0;
                Method *methods = class_copyMethodList(classes[i], &mc);
                for (unsigned int j = 0; j < mc; j++) {
                    KS(@"[XPF]     方法: %s", sel_getName(method_getName(methods[j])));
                }
                if (methods) free(methods);
            }
        }
        free(classes);
    }
}

#pragma mark - 自动发现验证方法

static void scanAndHookVerifyMethods(Class cls) {
    KS(@"[SCAN] 扫描 %s 的验证相关方法...", class_getName(cls));
    unsigned int mc = 0;
    Method *methods = class_copyMethodList(cls, &mc);
    int hooked = 0;
    for (unsigned int i = 0; i < mc; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        NSString *lower = [name lowercaseString];
        
        // 发现验证相关方法
        if ([lower containsString:@"verify"] || [lower containsString:@"check"] || 
            [lower containsString:@"auth"] || [lower containsString:@"activ"] || 
            [lower containsString:@"code"] || [lower containsString:@"license"] ||
            [lower containsString:@"login"] || [lower containsString:@"valid"]) {
            
            KS(@"[SCAN]   发现方法: %@", name);
            
            // Hook 这些方法
            __block IMP orig = method_getImplementation(methods[i]);
            IMP newIMP = imp_implementationWithBlock(^void(id self, ...) {
                KS(@"[ACT] ⭐ %@ 被调用", name);
                logStack(0, 4);
                injectFakeState();
                
                // 尝试获取参数（如果是 NSString 类型）
                va_list args;
                va_start(args, self);
                id arg1 = va_arg(args, id);
                va_end(args);
                if (arg1) KS(@"[ACT]   参数1: %@", arg1);
                
                // 调用原版
                // 注意：这里简化处理，实际应该用 NSInvocation 处理变参
                // 但为了兼容性，我们只 hook 无参和单参方法
                if ([name containsString:@":"]) {
                    // 有参数，尝试调用
                    @try {
                        if ([name hasSuffix:@":"]) {
                            // 单参数
                            ((void (*)(id, SEL, id))orig)(self, sel, arg1);
                        } else {
                            // 多参数，不处理
                            KS(@"[ACT]   多参数方法，跳过调用");
                        }
                    } @catch (NSException *e) {
                        KS(@"[ACT]   调用异常: %@", e.reason);
                    }
                } else {
                    // 无参
                    ((void (*)(id, SEL))orig)(self, sel);
                }
                
                // 如果这是验证方法，补全初始化链
                if ([lower containsString:@"verify"] || [lower containsString:@"check"] || [lower containsString:@"auth"]) {
                    runFullInitChain(self);
                }
            });
            method_setImplementation(methods[i], newIMP);
            hooked++;
        }
    }
    if (methods) free(methods);
    KS(@"[SCAN]   Hooked %d 个验证相关方法", hooked);
}

#pragma mark - Hook 入口

static void hookOnTapVerify(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (!m) { KS(@"[HOOK] ❌ onTapVerify not found"); return; }
    KS(@"[HOOK] ✅ onTapVerify");
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^void(id self) {
        KS(@"[ACT] ⭐ onTapVerify 拦截 — 开始自主验证");
        logStack(0, 3);
        injectFakeState();
        runFullInitChain(self);
    });
    method_setImplementation(m, newIMP);
}

static void hookShowSuccess(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(showSuccess:completion:));
    if (!m) return;
    KS(@"[HOOK] ✅ showSuccess:completion:");
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^void(id self, id msg, void (^completion)(void)) {
        KS(@"[ACT] ⭐ showSuccess: %@", msg);
        void (^wrapped)(void) = ^{
            if (completion) completion();
            KS(@"[ACT]   showSuccess completion 执行完毕");
        };
        ((void (*)(id, SEL, id, void (^)(void)))orig)(self, @selector(showSuccess:completion:), msg, wrapped);
    });
    method_setImplementation(m, newIMP);
}

static void hookSetupAfterActivation(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(setupAfterActivation));
    if (!m) return;
    KS(@"[HOOK] ✅ setupAfterActivation in %s", class_getName(cls));
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^void(id self) {
        KS(@"[MAIN] ⭐ setupAfterActivation START");
        logStack(0, 6);
        ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
        KS(@"[MAIN]   setupAfterActivation END");
    });
    method_setImplementation(m, newIMP);
}

static void hookStartContinuousAuthCheck(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(startContinuousAuthCheck));
    if (!m) return;
    KS(@"[HOOK] ✅ startContinuousAuthCheck in %s", class_getName(cls));
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^void(id self) {
        KS(@"[AUTH] ⭐ startContinuousAuthCheck START");
        logStack(0, 6);
        ((void (*)(id, SEL))orig)(self, @selector(startContinuousAuthCheck));
        KS(@"[AUTH]   startContinuousAuthCheck END");
    });
    method_setImplementation(m, newIMP);
}

#pragma mark - 构造函数

__attribute__((constructor))
static void ks_init(void) {
    NSLog(@"========================================");
    NSLog(@"[KfunSolo] v2 - Fixed Bypass");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_win = [[KSWindow alloc] init];
        
        KS(@"=== KfunSolo v2 启动 ===");
        KS(@"修正：");
        KS(@"1. buildSuccessViewWithExpire: 传入 NSString（不是 NSDate）");
        KS(@"2. 不手动 dismiss，让原版自己处理页面切换");
        KS(@"3. 自动扫描并 Hook 所有验证相关方法");
        KS(@"4. 增强主页查找逻辑（支持 TabBar/Nav/Modal）");
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
        
        Class actVC = objc_getClass("WWWActivationViewController");
        if (actVC) {
            hookOnTapVerify(actVC);
            hookShowSuccess(actVC);
            hookSetupAfterActivation(actVC);
            hookStartContinuousAuthCheck(actVC);
            scanAndHookVerifyMethods(actVC);  // ⭐ 自动扫描所有验证方法
        } else {
            KS(@"[INIT] ⚠️ WWWActivationViewController not found, retrying...");
        }
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) {
            hookSetupAfterActivation(mainVC);
            hookStartContinuousAuthCheck(mainVC);
            scanAndHookVerifyMethods(mainVC);
        } else {
            KS(@"[INIT] ⚠️ ViewController not found, retrying...");
        }
        
        if (!actVC || !mainVC) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!actVC) {
                    Class retry = objc_getClass("WWWActivationViewController");
                    if (retry) {
                        KS(@"[INIT] Retry: WWWActivationViewController");
                        hookOnTapVerify(retry);
                        hookShowSuccess(retry);
                        hookSetupAfterActivation(retry);
                        hookStartContinuousAuthCheck(retry);
                        scanAndHookVerifyMethods(retry);
                    }
                }
                if (!mainVC) {
                    Class retry = objc_getClass("ViewController");
                    if (retry) {
                        KS(@"[INIT] Retry: ViewController");
                        hookSetupAfterActivation(retry);
                        hookStartContinuousAuthCheck(retry);
                        scanAndHookVerifyMethods(retry);
                    }
                }
            });
        }
    });
}
