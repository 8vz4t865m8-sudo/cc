//
//  iphook_full.m - KFun 全面监控版 v3
//  保存为 iphook.m 直接编译
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>

#pragma mark - 日志系统

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunFull] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 30000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 30000)];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = g_logBuffer;
            [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)];
        }
    });
}
#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

#pragma mark - 悬浮窗

@interface LogDragHandler : NSObject
@end
@implementation LogDragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view.superview;
    CGPoint t = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}
- (void)copyLog:(id)sender {
    if (g_logBuffer.length > 0) {
        [UIPasteboard generalPasteboard].string = g_logBuffer;
        LOG(@"📋 已复制 %lu 字符", (unsigned long)g_logBuffer.length);
    }
}
@end
static LogDragHandler *g_drag = nil;

static void setupLogWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)s).activationState == UISceneActivationStateForegroundActive) {
                    kw = ((UIWindowScene *)s).windows.firstObject; break;
                }
            }
        }
        if (!kw) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            kw = [UIApplication sharedApplication].keyWindow;
            if (!kw) kw = [UIApplication sharedApplication].windows.firstObject;
            #pragma clang diagnostic pop
        }
        if (!kw) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupLogWindow(); }); return; }
        
        CGFloat w = 360, h = 340;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(8, 120, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.94];
        g_logContainer.layer.cornerRadius = 12;
        g_logContainer.layer.borderColor = [UIColor colorWithRed:0 green:0.8 blue:1 alpha:1].CGColor;
        g_logContainer.layer.borderWidth = 1.5;
        
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 30)];
        bar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        [g_logContainer addSubview:bar];
        
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, w-90, 22)];
        t.text = @"🔍 KFun 全面监控 (拖动)";
        t.textColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:1];
        t.font = [UIFont boldSystemFontOfSize:11];
        [bar addSubview:t];
        
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(w-80, 4, 75, 22);
        [btn setTitle:@"📋复制" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:10];
        [btn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        g_drag = [[LogDragHandler alloc] init];
        [btn addTarget:g_drag action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:btn];
        
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(3, 32, w-6, h-34)];
        g_logView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.3 alpha:1];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:8.5];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        [g_logContainer addSubview:g_logView];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_drag action:@selector(handlePan:)];
        [bar addGestureRecognizer:pan];
        
        [kw addSubview:g_logContainer];
        LOG(@"✅ 悬浮窗启动");
    });
}

#pragma mark - 工具：打印对象所有属性和 Ivar

static void dumpObj(id obj, NSString *label) {
    if (!obj) return;
    LOG(@"┌── 📸 [%@] %@", label, NSStringFromClass([obj class]));
    
    unsigned int n = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &n);
    for (unsigned int i = 0; i < n && i < 50; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            id v = [obj valueForKey:name];
            NSString *d = v ? [v description] : @"nil";
            if (d.length > 200) d = [d substringToIndex:200];
            LOG(@"│  %@ = %@", name, d);
        } @catch (NSException *e) {
            LOG(@"│  %@ = [err:%@]", name, e.reason);
        }
    }
    if (props) free(props);
    
    Ivar *ivars = class_copyIvarList(object_getClass(obj), &n);
    for (unsigned int i = 0; i < n && i < 30; i++) {
        NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i])];
        @try {
            id v = object_getIvar(obj, ivars[i]);
            NSString *d = v ? [v description] : @"nil";
            if (d.length > 200) d = [d substringToIndex:200];
            LOG(@"│  ivar %@ = %@", name, d);
        } @catch (NSException *e) {}
    }
    if (ivars) free(ivars);
    
    LOG(@"└── 📸 [%@] end", label);
}

#pragma mark - 1. 运行时枚举所有类，自动发现验证相关类

static void scanAllClasses() {
    LOG(@"🔍 开始扫描所有类...");
    int total = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * total);
    objc_getClassList(classes, total);
    
    NSMutableArray *authClasses = [NSMutableArray array];
    NSMutableArray *vcClasses = [NSMutableArray array];
    
    for (int i = 0; i < total; i++) {
        Class cls = classes[i];
        NSString *name = NSStringFromClass(cls);
        if (!name) continue;
        
        NSString *low = name.lowercaseString;
        if ([low containsString:@"auth"] || [low containsString:@"activ"] || 
            [low containsString:@"verify"] || [low containsString:@"code"] ||
            [low containsString:@"login"] || [low containsString:@"key"] ||
            [low containsString:@"mask"] || [low containsString:@"expire"]) {
            [authClasses addObject:name];
        }
        if ([cls isSubclassOfClass:[UIViewController class]]) {
            [vcClasses addObject:name];
        }
    }
    free(classes);
    
    LOG(@"🔍 发现 %d 个类，其中 VC 类 %lu 个", total, (unsigned long)vcClasses.count);
    LOG(@"🔍 疑似验证类 (%lu):", (unsigned long)authClasses.count);
    for (NSString *n in authClasses) LOG(@"   • %@", n);
}

#pragma mark - 2. Hook 任意类的所有方法（通用）

static void hookAllMethodsOfClass(Class cls, NSString *prefix) {
    if (!cls) return;
    unsigned int n = 0;
    Method *methods = class_copyMethodList(cls, &n);
    for (unsigned int i = 0; i < n; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        IMP orig = method_getImplementation(methods[i]);
        const char *typeEnc = method_getTypeEncoding(methods[i]);
        
        // 只 hook 关键方法，避免性能爆炸
        if ([name hasPrefix:@"init"] || [name hasPrefix:@"dealloc"] || 
            [name hasPrefix:@"_"] || [name isEqualToString:@"class"] ||
            [name isEqualToString:@"description"] || [name isEqualToString:@"debugDescription"]) {
            continue;
        }
        
        IMP newIMP = imp_implementationWithBlock(^(id self, ...) {
            LOG(@"[%@] → %@", prefix, name);
            // 尝试获取返回值类型
            char ret = typeEnc ? typeEnc[0] : 'v';
            if (ret == 'v') {
                ((void (*)(id, SEL))orig)(self, sel);
            } else {
                id r = ((id (*)(id, SEL))orig)(self, sel);
                if (r) LOG(@"[%@] ← %@ = %@", prefix, name, [r description]);
                return r;
            }
            return (id)nil;
        });
        class_replaceMethod(cls, sel, newIMP, typeEnc);
    }
    if (methods) free(methods);
}

#pragma mark - 3. 专门 Hook 验证相关类

static void hookAuthClasses() {
    int total = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * total);
    objc_getClassList(classes, total);
    
    for (int i = 0; i < total; i++) {
        Class cls = classes[i];
        NSString *name = NSStringFromClass(cls);
        if (!name) continue;
        
        NSString *low = name.lowercaseString;
        BOOL isAuth = ([low containsString:@"auth"] || [low containsString:@"activ"] || 
                       [low containsString:@"verify"] || [low containsString:@"code"] ||
                       [low containsString:@"login"] || [low containsString:@"key"] ||
                       [low containsString:@"mask"] || [low containsString:@"expire"]);
        
        if (isAuth && [cls isSubclassOfClass:[UIViewController class]]) {
            LOG(@"🎣 Hook 验证类: %@", name);
            hookAllMethodsOfClass(cls, name);
        }
    }
    free(classes);
}

#pragma mark - 4. Hook NSURLSession 全系列

static void hookNSURLSession() {
    Class cls = [NSURLSession class];
    
    // dataTaskWithRequest:
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURLRequest *req) {
            LOG(@"🌐 dataTaskWithRequest: %@ %@ body=%lu", req.URL, req.allHTTPHeaderFields, (unsigned long)req.HTTPBody.length);
            return ((id (*)(id, SEL, id))orig)(self, @selector(dataTaskWithRequest:), req);
        });
        class_replaceMethod(cls, @selector(dataTaskWithRequest:), newIMP, te);
    }
    
    // dataTaskWithURL:completionHandler:
    Method m2 = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURL *url, id completion) {
            LOG(@"🌐 dataTaskWithURL: %@", url.absoluteString);
            id wrap = ^(NSData *data, NSURLResponse *resp, NSError *err) {
                NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (id)resp : nil;
                LOG(@"🌐 响应 %@ | %ld | %lu bytes | err=%@", url.absoluteString, (long)(http?http.statusCode:0), (unsigned long)data.length, err);
                if (data && data.length < 3000) {
                    NSString *b = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (b) LOG(@"🌐 Body: %@", b);
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, resp, err);
            };
            return ((id (*)(id, SEL, NSURL*, id))orig)(self, @selector(dataTaskWithURL:completionHandler:), url, wrap);
        });
        class_replaceMethod(cls, @selector(dataTaskWithURL:completionHandler:), newIMP, te);
    }
    
    // dataTaskWithRequest:completionHandler:
    Method m3 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m3) {
        IMP orig = method_getImplementation(m3);
        const char *te = method_getTypeEncoding(m3);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURLRequest *req, id completion) {
            LOG(@"🌐 dataTaskWithRequest: %@ headers=%@", req.URL.absoluteString, req.allHTTPHeaderFields);
            id wrap = ^(NSData *data, NSURLResponse *resp, NSError *err) {
                if (data && data.length < 3000) {
                    NSString *b = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (b) LOG(@"🌐 Resp Body: %@", b);
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, resp, err);
            };
            return ((id (*)(id, SEL, id, id))orig)(self, @selector(dataTaskWithRequest:completionHandler:), req, wrap);
        });
        class_replaceMethod(cls, @selector(dataTaskWithRequest:completionHandler:), newIMP, te);
    }
    
    LOG(@"✅ NSURLSession 已监控");
}

#pragma mark - 5. Hook WKWebView 加载 & JS 通信

static void hookWKWebView() {
    Class wk = NSClassFromString(@"WKWebView");
    if (!wk) { LOG(@"❌ WKWebView 类未找到"); return; }
    
    // loadRequest:
    Method m1 = class_getInstanceMethod(wk, @selector(loadRequest:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURLRequest *req) {
            LOG(@"🌐 WK loadRequest: %@", req.URL.absoluteString);
            return ((id (*)(id, SEL, id))orig)(self, @selector(loadRequest:), req);
        });
        class_replaceMethod(wk, @selector(loadRequest:), newIMP, te);
    }
    
    // loadFileURL:allowingReadAccessToURL:
    Method m2 = class_getInstanceMethod(wk, @selector(loadFileURL:allowingReadAccessToURL:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURL *url, NSURL *base) {
            LOG(@"🌐 WK loadFileURL: %@", url);
            return ((id (*)(id, SEL, id, id))orig)(self, @selector(loadFileURL:allowingReadAccessToURL:), url, base);
        });
        class_replaceMethod(wk, @selector(loadFileURL:allowingReadAccessToURL:), newIMP, te);
    }
    
    // loadHTMLString:baseURL:
    Method m3 = class_getInstanceMethod(wk, @selector(loadHTMLString:baseURL:));
    if (m3) {
        IMP orig = method_getImplementation(m3);
        const char *te = method_getTypeEncoding(m3);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *str, NSURL *base) {
            LOG(@"🌐 WK loadHTMLString len=%lu base=%@", (unsigned long)str.length, base);
            // 把 HTML 内容也记录下来（可能有 WebSocket 地址）
            if (str.length < 5000) {
                NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(ws://|wss://|http://|https://)[^\\s\"'<>]+" options:0 error:nil];
                NSArray *matches = [re matchesInString:str options:0 range:NSMakeRange(0, str.length)];
                for (NSTextCheckingResult *r in matches) {
                    LOG(@"🌐 HTML 中发现 URL: %@", [str substringWithRange:r.range]);
                }
            }
            return ((id (*)(id, SEL, id, id))orig)(self, @selector(loadHTMLString:baseURL:), str, base);
        });
        class_replaceMethod(wk, @selector(loadHTMLString:baseURL:), newIMP, te);
    }
    
    // evaluateJavaScript:completionHandler:
    Method m4 = class_getInstanceMethod(wk, @selector(evaluateJavaScript:completionHandler:));
    if (m4) {
        IMP orig = method_getImplementation(m4);
        const char *te = method_getTypeEncoding(m4);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *js, id completion) {
            LOG(@"🌐 WK evaluateJS: %@", [js substringToIndex:MIN(300, js.length)]);
            id wrap = ^(id result, NSError *err) {
                LOG(@"🌐 JS Result: %@ | err=%@", result, err);
                if (completion) ((void(^)(id,NSError*))completion)(result, err);
            };
            return ((id (*)(id, SEL, id, id))orig)(self, @selector(evaluateJavaScript:completionHandler:), js, wrap);
        });
        class_replaceMethod(wk, @selector(evaluateJavaScript:completionHandler:), newIMP, te);
    }
    
    LOG(@"✅ WKWebView 已监控");
}

#pragma mark - 6. Hook WKUserContentController addScriptMessageHandler

static void hookWKScriptMessageHandler() {
    Class ucc = NSClassFromString(@"WKUserContentController");
    if (!ucc) return;
    
    Method m = class_getInstanceMethod(ucc, @selector(addScriptMessageHandler:name:));
    if (!m) return;
    
    IMP orig = method_getImplementation(m);
    const char *te = method_getTypeEncoding(m);
    IMP newIMP = imp_implementationWithBlock(^(id self, id handler, NSString *name) {
        LOG(@"🌐 WK 注册 JS Bridge: name=%@ handler=%@", name, NSStringFromClass([handler class]));
        return ((id (*)(id, SEL, id, id))orig)(self, @selector(addScriptMessageHandler:name:), handler, name);
    });
    class_replaceMethod(ucc, @selector(addScriptMessageHandler:name:), newIMP, te);
    LOG(@"✅ WKScriptMessageHandler 已监控");
}

#pragma mark - 7. Hook 关键属性 setter（authMaskView / codeField / successView）

static void hookPropertySetters(Class cls) {
    if (!cls) return;
    unsigned int n = 0;
    objc_property_t *props = class_copyPropertyList(cls, &n);
    for (unsigned int i = 0; i < n; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        if ([name isEqualToString:@"authMaskView"] || [name isEqualToString:@"codeField"] ||
            [name isEqualToString:@"successView"] || [name isEqualToString:@"errorLabel"] ||
            [name isEqualToString:@"verifyButton"]) {
            
            NSString *setterName = [NSString stringWithFormat:@"set%@:", [name capitalizedString]];
            SEL setterSel = NSSelectorFromString(setterName);
            Method m = class_getInstanceMethod(cls, setterSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                const char *te = method_getTypeEncoding(m);
                IMP newIMP = imp_implementationWithBlock(^(id self, id val) {
                    LOG(@"🔔 [%@] %@ = %@", NSStringFromClass(cls), name, val ? [val description] : @"nil");
                    ((void (*)(id, SEL, id))orig)(self, setterSel, val);
                });
                class_replaceMethod(cls, setterSel, newIMP, te);
            }
        }
    }
    if (props) free(props);
}

#pragma mark - 8. 监控所有 UIViewController 的 present/dismiss

static void hookAllViewControllers() {
    Class vc = [UIViewController class];
    
    Method m1 = class_getInstanceMethod(vc, @selector(presentViewController:animated:completion:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, UIViewController *vc2, BOOL anim, id completion) {
            LOG(@"📱 presentVC: %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc2 class]));
            dumpObj(vc2, [NSString stringWithFormat:@"Presented-%@", NSStringFromClass([vc2 class])]);
            ((void (*)(id, SEL, id, BOOL, id))orig)(self, @selector(presentViewController:animated:completion:), vc2, anim, completion);
        });
        class_replaceMethod(vc, @selector(presentViewController:animated:completion:), newIMP, te);
    }
    
    Method m2 = class_getInstanceMethod(vc, @selector(dismissViewControllerAnimated:completion:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL anim, id completion) {
            LOG(@"📱 dismissVC: %@", NSStringFromClass([self class]));
            ((void (*)(id, SEL, BOOL, id))orig)(self, @selector(dismissViewControllerAnimated:completion:), anim, completion);
        });
        class_replaceMethod(vc, @selector(dismissViewControllerAnimated:completion:), newIMP, te);
    }
    
    LOG(@"✅ UIViewController present/dismiss 已监控");
}

#pragma mark - 9. 尝试 Hook libcurl 层（如果应用静态链接了 curl）

static void (*orig_curl_easy_setopt)(void *, long, ...) = NULL;
static void hook_curl_setopt(void *curl, long option, ...) {
    va_list args;
    va_start(args, option);
    
    if (option == 10002) { // CURLOPT_URL
        char *url = va_arg(args, char*);
        LOG(@"🌐 curl URL: %s", url ? url : "(null)");
    } else if (option == 10005) { // CURLOPT_PROXY
        char *proxy = va_arg(args, char*);
        LOG(@"🌐 curl Proxy: %s", proxy ? proxy : "(null)");
    } else if (option == 64) { // CURLOPT_SSL_VERIFYPEER
        long v = va_arg(args, long);
        LOG(@"🌐 curl SSL_VERIFYPEER=%ld", v);
    }
    
    va_end(args);
    // 无法正确转发变参，这里只做记录，不实际 hook
}

#pragma mark - 10. 定时扫描：发现新类就 hook

static void startAutoHookTimer() {
    static NSMutableSet *hookedClasses = nil;
    if (!hookedClasses) hookedClasses = [NSMutableSet set];
    
    [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *timer) {
        int total = objc_getClassList(NULL, 0);
        Class *classes = (Class *)malloc(sizeof(Class) * total);
        objc_getClassList(classes, total);
        
        for (int i = 0; i < total; i++) {
            NSString *name = NSStringFromClass(classes[i]);
            if ([hookedClasses containsObject:name]) continue;
            [hookedClasses addObject:name];
            
            NSString *low = name.lowercaseString;
            if ([low containsString:@"auth"] || [low containsString:@"activ"] || 
                [low containsString:@"verify"] || [low containsString:@"code"] ||
                [low containsString:@"login"] || [low containsString:@"key"] ||
                [low containsString:@"mask"] || [low containsString:@"expire"] ||
                [low containsString:@"web"] || [low containsString:@"socket"]) {
                
                LOG(@"🔍 延迟发现新类: %@", name);
                hookAllMethodsOfClass(classes[i], name);
                hookPropertySetters(classes[i]);
            }
        }
        free(classes);
    }];
    
    LOG(@"✅ 自动扫描已启动 (每3秒)");
}

#pragma mark - Constructor

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunFull] 全面监控版 v3 已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        
        // 先扫描所有类
        scanAllClasses();
        
        // Hook 所有已知验证类
        hookAuthClasses();
        
        // Hook 网络层
        hookNSURLSession();
        
        // Hook WebView
        hookWKWebView();
        hookWKScriptMessageHandler();
        
        // Hook VC 生命周期
        hookAllViewControllers();
        
        // 监控属性 setter
        int total = objc_getClassList(NULL, 0);
        Class *classes = (Class *)malloc(sizeof(Class) * total);
        objc_getClassList(classes, total);
        for (int i = 0; i < total; i++) {
            hookPropertySetters(classes[i]);
        }
        free(classes);
        
        // 启动自动扫描
        startAutoHookTimer();
        
        LOG(@"🚀 全面监控系统已启动");
        LOG(@"📋 操作：输入真卡密 → 点验证 → 等进入主页面 → 点复制发给我");
    });
}
