//
//  KfunSpy.m
//  纯观察版 — 不替换任何方法，只记录调用链
//  用正确卡密验证一次，记录完整流程
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma mark - 日志

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
    static KSLogger *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; }); return s;
}
- (instancetype)init {
    self = [super init];
    _buffer = [NSMutableString string];
    _timeFmt = [[NSDateFormatter alloc] init];
    _timeFmt.dateFormat = @"HH:mm:ss.SSS";
    return self;
}
- (void)log:(NSString *)fmt, ... {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
    NSString *ts = [_timeFmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
    [_buffer appendString:line];
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [[docs firstObject] stringByAppendingPathComponent:@"kfun_spy.log"];
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
        t.text = @"🔍 KfunSpy"; t.font = [UIFont boldSystemFontOfSize:12];
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
        _console.font = [UIFont fontWithName:@"Courier" size:8];
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
        self.console.text = [NSString stringWithFormat:@"%@%@", self.console.text, n.object];
        [self.console scrollRangeToVisible:NSMakeRange(self.console.text.length-1, 1)];
    });
}
- (void)copyAll { UIPasteboard.generalPasteboard.string = [KSLogger shared].allText; }
- (void)clearAll { [[KSLogger shared] clear]; self.console.text = @""; }
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x+t.x, self.center.y+t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}
@end

static KSWindow *g_win = nil;

#pragma mark - 观察 Hook（不替换，只记录）

// 通用观察 hook：调用原始方法，前后打日志
static void makeSpyHook(Class cls, SEL sel, const char *label) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    
    IMP origIMP = method_getImplementation(m);
    const char *typeEnc = method_getTypeEncoding(m);
    
    // 根据 type encoding 创建合适的 spy block
    // 常见: v16@0:8 (无参), v24@0:8@16 (一个id参数), v32@0:8@16@24 (两个id参数)
    NSString *enc = [NSString stringWithUTF8String:typeEnc ?: ""];
    
    if ([enc hasPrefix:@"v16@0:8"]) {
        // void(void) - 无参数
        IMP spyIMP = imp_implementationWithBlock(^(id self) {
            KS(@"[👁] %s.%s START", class_getName(cls), sel_getName(sel));
            ((void (*)(id, SEL))origIMP)(self, sel);
            KS(@"[👁] %s.%s END", class_getName(cls), sel_getName(sel));
        });
        method_setImplementation(m, spyIMP);
    } else if ([enc hasPrefix:@"v24@0:8@16"]) {
        // void(id) - 一个id参数
        IMP spyIMP = imp_implementationWithBlock(^(id self, id arg) {
            NSString *argDesc = [arg respondsToSelector:@selector(description)] ? [arg description] : @"<non-desc>";
            if (argDesc.length > 200) argDesc = [argDesc substringToIndex:200];
            KS(@"[👁] %s.%s arg=%@", class_getName(cls), sel_getName(sel), argDesc);
            ((void (*)(id, SEL, id))origIMP)(self, sel, arg);
            KS(@"[👁] %s.%s END", class_getName(cls), sel_getName(sel));
        });
        method_setImplementation(m, spyIMP);
    } else if ([enc hasPrefix:@"v32@0:8@16@24"]) {
        // void(id, id) - 两个id参数（如 activateCode:completion:）
        IMP spyIMP = imp_implementationWithBlock(^(id self, id arg1, id arg2) {
            NSString *a1 = [arg1 respondsToSelector:@selector(description)] ? [arg1 description] : @"<non-desc>";
            if (a1.length > 200) a1 = [a1 substringToIndex:200];
            KS(@"[👁] %s.%s arg1=%@ arg2=%@", class_getName(cls), sel_getName(sel), a1, [arg2 class]);
            ((void (*)(id, SEL, id, id))origIMP)(self, sel, arg1, arg2);
            KS(@"[👁] %s.%s END", class_getName(cls), sel_getName(sel));
        });
        method_setImplementation(m, spyIMP);
    } else if ([enc hasPrefix:@"B16@0:8"]) {
        // BOOL(void)
        IMP spyIMP = imp_implementationWithBlock(^BOOL(id self) {
            KS(@"[👁] %s.%s START", class_getName(cls), sel_getName(sel));
            BOOL result = ((BOOL (*)(id, SEL))origIMP)(self, sel);
            KS(@"[👁] %s.%s → %d", class_getName(cls), sel_getName(sel), result);
            return result;
        });
        method_setImplementation(m, spyIMP);
    } else if ([enc hasPrefix:@"@16@0:8"]) {
        // id(void)
        IMP spyIMP = imp_implementationWithBlock(^id(id self) {
            KS(@"[👁] %s.%s START", class_getName(cls), sel_getName(sel));
            id result = ((id (*)(id, SEL))origIMP)(self, sel);
            KS(@"[👁] %s.%s → %@", class_getName(cls), sel_getName(sel), result);
            return result;
        });
        method_setImplementation(m, spyIMP);
    } else {
        // 未知签名，只记录调用
        KS(@"[SPY] ⚠️ %s.%s 未知签名: %s", class_getName(cls), sel_getName(sel), typeEnc ?: "?");
    }
    
    KS(@"[SPY] ✅ %s.%s 已安装观察 (type=%s)", class_getName(cls), sel_getName(sel), typeEnc ?: "?");
}

#pragma mark - 网络请求观察

// swizzle NSURLSession dataTaskWithRequest:completionHandler:
static void spyNetwork(void) {
    Class cls = [NSURLSession class];
    SEL sel = @selector(dataTaskWithRequest:completionHandler:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { KS(@"[SPY] ⚠️ dataTaskWithRequest: not found"); return; }
    
    IMP origIMP = method_getImplementation(m);
    IMP spyIMP = imp_implementationWithBlock(^(id self, NSURLRequest *req, void(^completion)(NSData*, NSURLResponse*, NSError*)) {
        NSString *url = req.URL.absoluteString;
        NSString *method = req.HTTPMethod ?: @"GET";
        NSData *body = req.HTTPBody;
        NSString *bodyStr = body ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : @"(nil)";
        if (bodyStr.length > 500) bodyStr = [bodyStr substringToIndex:500];
        
        KS(@"[NET] %@ %@", method, url);
        if (body) KS(@"[NET]   body=%@", bodyStr);
        for (NSString *key in req.allHTTPHeaderFields) {
            KS(@"[NET]   header: %@ = %@", key, req.allHTTPHeaderFields[key]);
        }
        
        // 包装 completion 打印响应
        void(^wrappedCompletion)(NSData*, NSURLResponse*, NSError*) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
            NSString *respStr = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(nil)";
            if (respStr.length > 500) respStr = [respStr substringToIndex:500];
            KS(@"[NET]   ← %ld err=%@", (long)httpResp.statusCode, err.localizedDescription ?: @"(nil)");
            KS(@"[NET]   ← body=%@", respStr);
            if (completion) completion(data, resp, err);
        };
        
        return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest*, void(^)(NSData*, NSURLResponse*, NSError*)))origIMP)(self, sel, req, wrappedCompletion);
    });
    method_setImplementation(m, spyIMP);
    KS(@"[SPY] ✅ NSURLSession.dataTaskWithRequest: 已安装网络观察");
}

#pragma mark - 全局扫描

static void scanAll(void) {
    KS(@"[SCAN] === 全局扫描所有类的方法 ===");
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    objc_getClassList(classes, numClasses);
    
    for (int i = 0; i < numClasses; i++) {
        const char *name = class_getName(classes[i]);
        // 只扫描 app 相关的类
        if (strstr(name, "WWW") || strstr(name, "ViewController") || 
            strstr(name, "RunInBackground") || strstr(name, "Activation") ||
            strstr(name, "Auth") || strstr(name, "Radar") || strstr(name, "Encryption")) {
            unsigned int mc = 0;
            Method *methods = class_copyMethodList(classes[i], &mc);
            if (!methods) continue;
            KS(@"[SCAN] %s (%d methods):", name, mc);
            for (unsigned int j = 0; j < mc; j++) {
                SEL sel = method_getName(methods[j]);
                const char *typeEnc = method_getTypeEncoding(methods[j]);
                KS(@"[SCAN]   %s (%s)", sel_getName(sel), typeEnc ?: "?");
            }
            free(methods);
        }
    }
    free(classes);
    KS(@"[SCAN] === 扫描完成 ===");
}

#pragma mark - 构造函数

__attribute__((constructor))
static void ks_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_win = [[KSWindow alloc] init];
        KS(@"=== KfunSpy 纯观察版启动 ===");
        KS(@"用正确卡密验证一次，记录完整流程");
        KS(@"");
        
        // 全局扫描
        scanAll();
        
        // 安装网络观察
        spyNetwork();
        
        // 观察 WWWActivationViewController 的关键方法
        Class actVC = objc_getClass("WWWActivationViewController");
        if (actVC) {
            KS(@"[SPY] --- 观察 WWWActivationViewController ---");
            makeSpyHook(actVC, @selector(onTapVerify), "tap");
            makeSpyHook(actVC, @selector(onVerify), "verify_block");
            makeSpyHook(actVC, @selector(setOnVerify:), "set_verify_block");
            makeSpyHook(actVC, @selector(prefillCode:), "prefill");
            makeSpyHook(actVC, @selector(viewDidLoad), "lifecycle");
            makeSpyHook(actVC, @selector(viewDidAppear:), "lifecycle");
        }
        
        // 观察 WWWActivation
        Class activation = objc_getClass("WWWActivation");
        if (activation) {
            KS(@"[SPY] --- 观察 WWWActivation ---");
            makeSpyHook(activation, @selector(activateCode:completion:), "activate");
            makeSpyHook(activation, @selector(activationStampPath), "stamp");
        }
        
        // 观察 ViewController
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) {
            KS(@"[SPY] --- 观察 ViewController ---");
            makeSpyHook(mainVC, @selector(viewDidLoad), "lifecycle");
            makeSpyHook(mainVC, @selector(viewDidAppear:), "lifecycle");
            makeSpyHook(mainVC, @selector(setupAfterActivation), "setup");
            makeSpyHook(mainVC, @selector(setupBackgroundKeepAlive), "bg");
            makeSpyHook(mainVC, @selector(startContinuousAuthCheck), "auth");
            makeSpyHook(mainVC, @selector(startRunInbackGround), "bg");
            makeSpyHook(mainVC, @selector(radarCollectLoop), "radar");
            makeSpyHook(mainVC, @selector(radarPushLoop), "radar");
            makeSpyHook(mainVC, @selector(readLoop), "read");
            makeSpyHook(mainVC, @selector(checkTask), "check");
            makeSpyHook(mainVC, @selector(authMaskView), "auth");
            makeSpyHook(mainVC, @selector(setAuthMaskView:), "auth");
        }
        
        // 观察 RunInBackground
        Class runBG = objc_getClass("RunInBackground");
        if (runBG) {
            KS(@"[SPY] --- 观察 RunInBackground ---");
            makeSpyHook(runBG, @selector(checkTask), "check");
        }
        
        // 观察 AppDelegate
        Class appDelegate = objc_getClass("AppDelegate");
        if (appDelegate) {
            KS(@"[SPY] --- 观察 AppDelegate ---");
            makeSpyHook(appDelegate, @selector(application:didFinishLaunchingWithOptions:), "launch");
        }
        
        // 观察 SceneDelegate
        Class sceneDelegate = objc_getClass("SceneDelegate");
        if (sceneDelegate) {
            KS(@"[SPY] --- 观察 SceneDelegate ---");
            makeSpyHook(sceneDelegate, @selector(scene:willConnectToSession:options:), "scene");
        }
        
        KS(@"[SPY] ✅ 所有观察点已安装");
        KS(@"[SPY] 现在用正确卡密验证...");
    });
}

#pragma clang diagnostic pop
