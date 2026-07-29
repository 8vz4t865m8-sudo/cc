//
//  KFunAutopsy.m
//  纯 clang 编译版本，无 Theos/Logos 依赖
//  编译命令：
//  clang -arch arm64 \
//    -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//    -framework UIKit -framework Foundation \
//    -lobjc -miphoneos-version-min=15.0 -fobjc-arc \
//    -dynamiclib -O2 -Wl,-undefined,dynamic_lookup \
//    KFunAutopsy.m -o KFunAutopsy.dylib
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#pragma mark - 日志引擎

@interface KFALogger : NSObject
+ (instancetype)shared;
- (void)log:(NSString *)fmt, ...;
- (NSString *)allText;
- (void)clear;
@property (nonatomic, strong) NSMutableString *buffer;
@property (nonatomic, strong) NSDateFormatter *timeFmt;
@end

@implementation KFALogger
+ (instancetype)shared {
    static KFALogger *s;
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
    
    NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *logPath = [[docPaths firstObject] stringByAppendingPathComponent:@"kfun_autopsy.log"];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"KFALogAppend" object:line];
}
- (NSString *)allText { return [_buffer copy]; }
- (void)clear {
    [_buffer setString:@""];
    NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *logPath = [[docPaths firstObject] stringByAppendingPathComponent:@"kfun_autopsy.log"];
    [[@"" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:logPath atomically:YES];
}
@end

#define KFA(fmt, ...) [[KFALogger shared] log:fmt, ##__VA_ARGS__]

#pragma mark - 悬浮解剖窗

@interface KFAWindow : UIWindow
@property (nonatomic, strong) UITextView *console;
@property (nonatomic, strong) UIView *topBar;
@end

@implementation KFAWindow

- (instancetype)init {
    CGRect sr = [UIScreen mainScreen].bounds;
    CGFloat W = sr.size.width * 0.88;
    CGFloat H = sr.size.height * 0.50;
    self = [super initWithFrame:CGRectMake((sr.size.width - W) / 2, 60, W, H)];
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
                    self.windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
        
        _topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 34)];
        _topBar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
        [self addSubview:_topBar];
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, W - 140, 26)];
        title.text = @"🔬 KFun Autopsy";
        title.font = [UIFont boldSystemFontOfSize:12];
        title.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.5 alpha:1.0];
        [_topBar addSubview:title];
        
        UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
        cp.frame = CGRectMake(W - 130, 2, 60, 30);
        [cp setTitle:@"📋复制" forState:UIControlStateNormal];
        cp.titleLabel.font = [UIFont systemFontOfSize:11];
        [cp setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
        [cp addTarget:self action:@selector(copyAll) forControlEvents:UIControlEventTouchUpInside];
        [_topBar addSubview:cp];
        
        UIButton *cl = [UIButton buttonWithType:UIButtonTypeSystem];
        cl.frame = CGRectMake(W - 65, 2, 60, 30);
        [cl setTitle:@"🗑清空" forState:UIControlStateNormal];
        cl.titleLabel.font = [UIFont systemFontOfSize:11];
        [cl setTitleColor:[UIColor orangeColor] forState:UIControlStateNormal];
        [cl addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
        [_topBar addSubview:cl];
        
        _console = [[UITextView alloc] initWithFrame:CGRectMake(3, 38, W - 6, H - 42)];
        _console.backgroundColor = [UIColor clearColor];
        _console.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.4 alpha:1.0];
        _console.font = [UIFont fontWithName:@"Courier" size:9];
        _console.editable = NO;
        _console.selectable = YES;
        _console.showsVerticalScrollIndicator = YES;
        [self addSubview:_console];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [_topBar addGestureRecognizer:pan];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNewLine:) name:@"KFALogAppend" object:nil];
    }
    return self;
}

- (void)onNewLine:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = n.object;
        self.console.text = [NSString stringWithFormat:@"%@%@", self.console.text, line];
        [self.console scrollRangeToVisible:NSMakeRange(self.console.text.length - 1, 1)];
    });
}

- (void)copyAll {
    UIPasteboard.generalPasteboard.string = [KFALogger shared].allText;
    KFA(@"[SYS] 全部日志已复制到剪贴板");
}

- (void)clearAll {
    [[KFALogger shared] clear];
    self.console.text = @"";
    KFA(@"=== 日志已清空 ===");
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

@end

static KFAWindow *g_win = nil;

#pragma mark - 辅助函数

static void dumpDict(id obj, int depth) {
    if (!obj || ![obj isKindOfClass:[NSDictionary class]]) {
        KFA(@"%@⚠️ 非字典: %@ (%@)", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], obj, NSStringFromClass([obj class]));
        return;
    }
    NSDictionary *d = obj;
    for (id k in d) {
        id v = d[k];
        NSString *ind = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
        if ([v isKindOfClass:[NSDictionary class]]) {
            KFA(@"%@\"%@\" → {", ind, k);
            dumpDict(v, depth + 1);
            KFA(@"%@}", ind);
        } else if ([v isKindOfClass:[NSArray class]]) {
            KFA(@"%@\"%@\" → [%lu]", ind, k, (unsigned long)[(NSArray *)v count]);
            for (id item in (NSArray *)v) KFA(@"%@  · %@", ind, item);
        } else {
            NSString *desc = [v description];
            if (desc.length > 120) desc = [desc substringToIndex:120];
            KFA(@"%@\"%@\" = \"%@\" [%@]", ind, k, desc, NSStringFromClass([v class]));
        }
    }
}

static void logStack(int skip, int max) {
    NSArray *syms = [NSThread callStackSymbols];
    for (int i = skip + 2; i < MIN((int)syms.count, skip + 2 + max); i++) {
        KFA(@"  ↳ %@", syms[i]);
    }
}

#pragma mark - Hook 1: WWWActivationViewController

static void hookActivationVC(Class cls) {
    if (!cls) { KFA(@"[INIT] ❌ WWWActivationViewController not found"); return; }
    KFA(@"[INIT] Hooking WWWActivationViewController");
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self) {
            KFA(@"[ACT] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, BOOL animated) {
            KFA(@"[ACT] viewDidAppear");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ viewDidAppear:");
    }
    
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self) {
            KFA(@"[ACT] ⭐ onTapVerify triggered");
            logStack(0, 4);
            ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ onTapVerify");
    }
    
    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, NSString *code, void (^completion)(BOOL, id)) {
            KFA(@"[ACT] ⭐ activateCode: \"%@\"", code);
            logStack(0, 3);
            void (^wrapped)(BOOL, id) = ^(BOOL success, id data) {
                KFA(@"[ACT] ⭐ activateCode completion callback");
                KFA(@"[ACT]   success = %d", success);
                KFA(@"[ACT]   data class = %@", NSStringFromClass([data class]));
                if ([data isKindOfClass:[NSDictionary class]]) {
                    KFA(@"[ACT]   data structure:");
                    dumpDict(data, 1);
                } else if (data) {
                    KFA(@"[ACT]   data = %@", [data description]);
                }
                if (completion) completion(success, data);
            };
            ((void (*)(id, SEL, NSString *, void (^)(BOOL, id)))orig)(self, @selector(activateCode:completion:), code, wrapped);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ activateCode:completion:");
    }
    
    m = class_getInstanceMethod(cls, @selector(showSuccess:completion:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, id msg, void (^completion)(void)) {
            KFA(@"[ACT] ⭐ showSuccess: %@", msg);
            KFA(@"[ACT]   completion block = %@", completion);
            void (^wrapped)(void) = ^{
                KFA(@"[ACT] ⭐ showSuccess completion block START");
                logStack(0, 6);
                if (completion) completion();
                KFA(@"[ACT]   showSuccess completion block END");
            };
            ((void (*)(id, SEL, id, void (^)(void)))orig)(self, @selector(showSuccess:completion:), msg, wrapped);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ showSuccess:completion:");
    }
    
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, id msg) {
            KFA(@"[ACT] showError: %@", msg);
            logStack(0, 4);
            ((void (*)(id, SEL, id))orig)(self, @selector(showError:), msg);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ showError:");
    }
    
    m = class_getInstanceMethod(cls, @selector(buildSuccessViewWithExpire:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, id expire) {
            KFA(@"[ACT] buildSuccessViewWithExpire: %@", expire);
            logStack(0, 4);
            ((void (*)(id, SEL, id))orig)(self, @selector(buildSuccessViewWithExpire:), expire);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ buildSuccessViewWithExpire:");
    }
    
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^BOOL(id self) {
            BOOL v = ((BOOL (*)(id, SEL))orig)(self, @selector(isActivated));
            KFA(@"[ACT] isActivated → %d", v);
            return v;
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ isActivated");
    }
    
    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^BOOL(id self) {
            BOOL v = ((BOOL (*)(id, SEL))orig)(self, @selector(isVerified));
            KFA(@"[ACT] isVerified → %d", v);
            return v;
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ isVerified");
    }
}

#pragma mark - Hook 2: ViewController

static void hookViewController(Class cls) {
    if (!cls) { KFA(@"[INIT] ❌ ViewController not found"); return; }
    KFA(@"[INIT] Hooking ViewController");
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self) {
            KFA(@"[MAIN] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, BOOL animated) {
            KFA(@"[MAIN] viewDidAppear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ viewDidAppear:");
    }
    
    m = class_getInstanceMethod(cls, @selector(setupAfterActivation));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self) {
            KFA(@"[MAIN] ⭐ setupAfterActivation called");
            logStack(0, 5);
            ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ setupAfterActivation");
    }
    
    m = class_getInstanceMethod(cls, @selector(setupBackgroundKeepAlive));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self) {
            KFA(@"[MAIN] setupBackgroundKeepAlive called");
            ((void (*)(id, SEL))orig)(self, @selector(setupBackgroundKeepAlive));
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ setupBackgroundKeepAlive");
    }
    
    m = class_getInstanceMethod(cls, @selector(tableView:numberOfRowsInSection:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^NSInteger(id self, UITableView *tv, NSInteger section) {
            NSInteger n = ((NSInteger (*)(id, SEL, UITableView *, NSInteger))orig)(self, @selector(tableView:numberOfRowsInSection:), tv, section);
            KFA(@"[MAIN] tableView rows=%ld (section=%ld)", (long)n, (long)section);
            return n;
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ tableView:numberOfRowsInSection:");
    }
    
    m = class_getInstanceMethod(cls, @selector(tableView:cellForRowAtIndexPath:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^UITableViewCell *(id self, UITableView *tv, NSIndexPath *ip) {
            UITableViewCell *c = ((UITableViewCell *(*)(id, SEL, UITableView *, NSIndexPath *))orig)(self, @selector(tableView:cellForRowAtIndexPath:), tv, ip);
            KFA(@"[MAIN] tableView cell[%ld,%ld] = \"%@\"", (long)ip.section, (long)ip.row, c.textLabel.text);
            return c;
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ tableView:cellForRowAtIndexPath:");
    }
    
    m = class_getInstanceMethod(cls, @selector(tableView));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^id(id self) {
            id v = ((id (*)(id, SEL))orig)(self, @selector(tableView));
            KFA(@"[MAIN] getter tableView → %@", v ? @"non-nil" : @"nil");
            return v;
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ tableView getter");
    }
    
    m = class_getInstanceMethod(cls, @selector(langSeg));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^id(id self) {
            id v = ((id (*)(id, SEL))orig)(self, @selector(langSeg));
            KFA(@"[MAIN] getter langSeg → %@", v ? @"non-nil" : @"nil");
            return v;
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ langSeg getter");
    }
}

#pragma mark - Hook 3: NSURLSession

static void hookNSURLSession(void) {
    Class cls = [NSURLSession class];
    Method m = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (!m) { KFA(@"[INIT] ❌ NSURLSession dataTaskWithRequest: not found"); return; }
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^NSURLSessionDataTask *(NSURLSession *self, NSURLRequest *req, void (^cb)(NSData *, NSURLResponse *, NSError *)) {
        KFA(@"[NET] %@ %@", req.HTTPMethod, req.URL.absoluteString);
        if (req.HTTPBody) {
            NSString *b = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
            if (b) KFA(@"[NET] BODY: %@", b);
        }
        if (req.allHTTPHeaderFields) KFA(@"[NET] HDR: %@", req.allHTTPHeaderFields);
        
        void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
            NSHTTPURLResponse *h = (NSHTTPURLResponse *)r;
            if (h) KFA(@"[NET] RESP %ld ← %@", (long)h.statusCode, h.URL.absoluteString);
            if (e) KFA(@"[NET] ERR: %@", e);
            if (d) {
                NSString *t = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                if (t && t.length < 800) {
                    KFA(@"[NET] DATA: %@", t);
                    id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
                    if ([j isKindOfClass:[NSDictionary class]]) { KFA(@"[NET] JSON:"); dumpDict(j, 1); }
                } else if (t) {
                    KFA(@"[NET] DATA: (text, %lu chars)", (unsigned long)t.length);
                } else {
                    KFA(@"[NET] DATA: (binary, %lu bytes)", (unsigned long)d.length);
                }
            }
            if (cb) cb(d, r, e);
        };
        return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig)(self, @selector(dataTaskWithRequest:completionHandler:), req, wrapped);
    });
    method_setImplementation(m, newIMP);
    KFA(@"[INIT]   ✅ NSURLSession dataTaskWithRequest:");
}

#pragma mark - Hook 4: NSUserDefaults

static void hookNSUserDefaults(void) {
    Class cls = [NSUserDefaults class];
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(setObject:forKey:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, id obj, NSString *key) {
            KFA(@"[STORE] SET \"%@\" = \"%@\"", key, obj);
            ((void (*)(id, SEL, id, NSString *))orig)(self, @selector(setObject:forKey:), obj, key);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ NSUserDefaults setObject:forKey:");
    }
    
    m = class_getInstanceMethod(cls, @selector(objectForKey:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^id(id self, NSString *key) {
            id v = ((id (*)(id, SEL, NSString *))orig)(self, @selector(objectForKey:), key);
            NSArray *keys = @[@"auth", @"token", @"license", @"expire", @"kfun", @"xpf", @"config", @"verify", @"status", @"user", @"device"];
            for (NSString *k in keys) {
                if ([key containsString:k]) {
                    KFA(@"[STORE] GET \"%@\" = \"%@\"", key, v);
                    break;
                }
            }
            return v;
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ NSUserDefaults objectForKey:");
    }
    
    m = class_getInstanceMethod(cls, @selector(setInteger:forKey:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, NSInteger value, NSString *key) {
            KFA(@"[STORE] SET_INT \"%@\" = %ld", key, (long)value);
            ((void (*)(id, SEL, NSInteger, NSString *))orig)(self, @selector(setInteger:forKey:), value, key);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ NSUserDefaults setInteger:forKey:");
    }
    
    m = class_getInstanceMethod(cls, @selector(setBool:forKey:));
    if (m) {
        __block IMP orig = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^void(id self, BOOL value, NSString *key) {
            KFA(@"[STORE] SET_BOOL \"%@\" = %d", key, value);
            ((void (*)(id, SEL, BOOL, NSString *))orig)(self, @selector(setBool:forKey:), value, key);
        });
        method_setImplementation(m, newIMP);
        KFA(@"[INIT]   ✅ NSUserDefaults setBool:forKey:");
    }
}

#pragma mark - Hook 5: UIAlertController

static void hookUIAlertController(void) {
    Class cls = [UIAlertController class];
    Method m = class_getClassMethod(cls, @selector(alertControllerWithTitle:message:preferredStyle:));
    if (!m) { KFA(@"[INIT] ❌ UIAlertController class method not found"); return; }
    
    __block IMP orig = method_getImplementation(m);
    IMP newIMP = imp_implementationWithBlock(^id(id self, NSString *title, NSString *message, UIAlertControllerStyle style) {
        KFA(@"[ALERT] TITLE: \"%@\"", title);
        KFA(@"[ALERT] MSG: \"%@\"", message);
        logStack(0, 5);
        return ((id (*)(id, SEL, NSString *, NSString *, UIAlertControllerStyle))orig)(self, @selector(alertControllerWithTitle:message:preferredStyle:), title, message, style);
    });
    method_setImplementation(m, newIMP);
    KFA(@"[INIT]   ✅ UIAlertController alertControllerWithTitle:");
}

#pragma mark - Hook 6: 全局查找 startContinuousAuthCheck

static void hookContinuousAuthCheck(void) {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) { KFA(@"[INIT] No classes found"); return; }
    
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    objc_getClassList(classes, numClasses);
    int hooked = 0;
    
    for (int i = 0; i < numClasses; i++) {
        if (class_respondsToSelector(classes[i], @selector(startContinuousAuthCheck))) {
            const char *clsName = class_getName(classes[i]);
            KFA(@"[INIT] Found startContinuousAuthCheck in class: %s", clsName);
            
            Method m = class_getInstanceMethod(classes[i], @selector(startContinuousAuthCheck));
            if (m) {
                __block IMP orig = method_getImplementation(m);
                IMP newIMP = imp_implementationWithBlock(^void(id self) {
                    KFA(@"[AUTH] ⭐ startContinuousAuthCheck called in %s", clsName);
                    logStack(0, 6);
                    ((void (*)(id, SEL))orig)(self, @selector(startContinuousAuthCheck));
                });
                method_setImplementation(m, newIMP);
                hooked++;
            }
        }
    }
    free(classes);
    KFA(@"[INIT]   ✅ startContinuousAuthCheck hooked in %d class(es)", hooked);
}

#pragma mark - 观察 libxpf.dylib 加载

static void checkLibxpfLoaded(void) {
    static BOOL found = NO;
    if (found) return;
    
    unsigned int count = _dyld_image_count();
    for (unsigned int i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "libxpf.dylib")) {
            found = YES;
            KFA(@"[DYLIB] ⭐ libxpf.dylib detected at index %d: %s", i, name);
            
            void *handle = dlopen(name, RTLD_NOLOAD);
            if (handle) {
                KFA(@"[DYLIB] handle = %p", handle);
                const char *syms[] = {"xpf_init", "xpf_start", "xpf_find_cpu_ttep", "xpf_find_allproc", "xpf_find_arm_vm_init"};
                for (int j = 0; j < 5; j++) {
                    void *addr = dlsym(handle, syms[j]);
                    if (addr) KFA(@"[DYLIB] %s = %p", syms[j], addr);
                }
            } else {
                KFA(@"[DYLIB] dlopen(RTLD_NOLOAD) failed");
            }
            return;
        }
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        checkLibxpfLoaded();
    });
}

#pragma mark - 构造函数

__attribute__((constructor))
static void kfa_init(void) {
    NSLog(@"========================================");
    NSLog(@"[KFunAutopsy] Pure clang version loaded");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_win = [[KFAWindow alloc] init];
        
        KFA(@"=== KFun Autopsy 启动 ===");
        KFA(@"使用说明：");
        KFA(@"1. 输入正版卡密，点击验证");
        KFA(@"2. 观察 [ACT] 激活流程 和 [NET] 网络请求");
        KFA(@"3. 观察 [MAIN] 主页加载 和 [STORE] 数据存储");
        KFA(@"4. 点击 📋复制，把日志发给我");
        KFA(@"5. 重点观察 ⭐ 标记的关键节点");
        
        Class actVC = objc_getClass("WWWActivationViewController");
        if (actVC) hookActivationVC(actVC);
        else KFA(@"[INIT] ⚠️ WWWActivationViewController not found, will retry in 3s");
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        else KFA(@"[INIT] ⚠️ ViewController not found, will retry in 3s");
        
        hookNSURLSession();
        hookNSUserDefaults();
        hookUIAlertController();
        hookContinuousAuthCheck();
        checkLibxpfLoaded();
        
        unsigned int imgCount = _dyld_image_count();
        for (unsigned int i = 0; i < imgCount; i++) {
            const char *n = _dyld_get_image_name(i);
            if (strstr(n, "xpf") || strstr(n, "kfun") || strstr(n, "inject") || strstr(n, "substrate") || strstr(n, "Autopsy")) {
                KFA(@"[IMG] %s", n);
            }
        }
        
        // 如果类没找到，延迟重试（有些类是懒加载的）
        if (!actVC || !mainVC) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!actVC) {
                    Class retryAct = objc_getClass("WWWActivationViewController");
                    if (retryAct) { KFA(@"[INIT] Retry: found WWWActivationViewController"); hookActivationVC(retryAct); }
                }
                if (!mainVC) {
                    Class retryMain = objc_getClass("ViewController");
                    if (retryMain) { KFA(@"[INIT] Retry: found ViewController"); hookViewController(retryMain); }
                }
            });
        }
    });
}
