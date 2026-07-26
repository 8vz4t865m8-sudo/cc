//
//  iphook.m - KFun 真卡密记录版
//  目标：记录正常验证流程的完整调用链，不干扰正常流程
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunRec] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 20000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 20000)];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = g_logBuffer;
            [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)];
        }
    });
}

@interface LogDragHandler : NSObject
@end
@implementation LogDragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view.superview;
    CGPoint t = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + t.x, view.center.y + t.y);
    [pan setTranslation:CGPointZero inView:view.superview];
}
- (void)copyLog:(id)sender {
    if (g_logBuffer && g_logBuffer.length > 0) {
        UIPasteboard.generalPasteboard.string = g_logBuffer;
        LOG(@"📋 已复制 (%lu 字符)", (unsigned long)g_logBuffer.length);
    }
}
@end
static LogDragHandler *g_dragHandler = nil;

static void setupLogWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)scene).activationState == UISceneActivationStateForegroundActive) {
                    if (((UIWindowScene *)scene).windows.count > 0) { keyWindow = ((UIWindowScene *)scene).windows.firstObject; break; }
                }
            }
        }
        if (!keyWindow) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
            if (!keyWindow && [UIApplication sharedApplication].windows.count > 0) keyWindow = [UIApplication sharedApplication].windows[0];
            #pragma clang diagnostic pop
        }
        if (!keyWindow) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupLogWindow(); }); return; }
        
        CGFloat w = 350, h = 300;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(8, 100, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.93];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor cyanColor].CGColor;
        g_logContainer.layer.borderWidth = 1.2;
        
        UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 28)];
        titleBar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        [g_logContainer addSubview:titleBar];
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(6, 3, w-80, 22)];
        title.text = @"🔍 KFun 记录版 (拖动)";
        title.textColor = [UIColor cyanColor];
        title.font = [UIFont boldSystemFontOfSize:10];
        [titleBar addSubview:title];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w-70, 3, 65, 22);
        [copyBtn setTitle:@"📋复制" forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont systemFontOfSize:9];
        [copyBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        g_dragHandler = [[LogDragHandler alloc] init];
        [copyBtn addTarget:g_dragHandler action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [titleBar addSubview:copyBtn];
        
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 30, w-4, h-32)];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:8];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = YES;
        [g_logContainer addSubview:g_logView];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_dragHandler action:@selector(handlePan:)];
        [titleBar addGestureRecognizer:pan];
        
        [keyWindow addSubview:g_logContainer];
        LOG(@"✅ 悬浮窗已启动");
    });
}

static void snapshotProperties(id obj, NSString *label) {
    if (!obj) return;
    LOG(@"📸 [%@] begin", label);
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            id val = [obj valueForKey:name];
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 120) desc = [desc substringToIndex:120];
            LOG(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {
            LOG(@"   %@ = [err:%@]", name, e.reason);
        }
    }
    if (props) free(props);
    LOG(@"📸 [%@] end", label);
}

// ============================================================
// 网络记录
// ============================================================
static void recordNetwork() {
    Class cls = [NSURLSession class];
    Method m = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (!m) return;
    IMP orig = method_getImplementation(m);
    const char *typeEnc = method_getTypeEncoding(m);
    IMP newIMP = imp_implementationWithBlock(^(id self, NSURL *url, id completion) {
        LOG(@"🌐 请求: %@", url.absoluteString);
        id wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
            LOG(@"🌐 响应: %@ | %ld | %@", url.absoluteString, (long)(http?http.statusCode:0), error?error.localizedDescription:@"ok");
            if (data && data.length < 2000) {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (body) LOG(@"🌐 Body: %@", body);
            }
            if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, response, error);
        };
        return ((id (*)(id, SEL, NSURL*, id))orig)(self, @selector(dataTaskWithURL:completionHandler:), url, wrapped);
    });
    class_replaceMethod(cls, @selector(dataTaskWithURL:completionHandler:), newIMP, typeEnc);
    LOG(@"✅ 网络记录已启用");
}

// ============================================================
// 通用方法拦截（只记录，不打断）
// ============================================================
static void hookAndLogAllMethods(Class cls, NSString *label) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *selName = NSStringFromSelector(sel);
        // 跳过系统高频方法
        if ([selName hasPrefix:@"_"] || [selName isEqualToString:@"dealloc"] ||
            [selName isEqualToString:@"description"] || [selName isEqualToString:@"debugDescription"] ||
            [selName isEqualToString:@"hash"] || [selName isEqualToString:@"isEqual:"]) continue;
        
        IMP origIMP = method_getImplementation(methods[i]);
        method_setImplementation(methods[i], imp_implementationWithBlock(^(id self, ...) {
            LOG(@"🎣 [%@] %@ 被调用", label, selName);
            return ((id (*)(id, SEL))origIMP)(self, sel);
        }));
    }
    if (methods) free(methods);
    LOG(@"✅ %@ 已记录 %u 个方法", label, count);
}

// ============================================================
// 监控 onVerify 和 state 变化
// ============================================================
static __weak id g_actVC = nil;

static void startMonitoring() {
    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) {
        // 监控 ActVC 的 onVerify
        if (g_actVC) {
            @try {
                static id lastOnVerify = nil;
                id current = [g_actVC valueForKey:@"onVerify"];
                if (current != lastOnVerify) {
                    LOG(@"🔔 [ActVC] onVerify 变化: %@ -> %@", lastOnVerify?@"非nil":@"nil", current?@"非nil":@"nil");
                    if (!current && lastOnVerify) {
                        LOG(@"🎉 onVerify 被调用并置为 nil！");
                        LOG(@"   调用栈:");
                        for (NSString *line in [NSThread callStackSymbols]) {
                            LOG(@"   📞 %@", line);
                        }
                        snapshotProperties(g_actVC, @"ActVC(onVerify调用后)");
                    }
                    lastOnVerify = current;
                }
            } @catch (NSException *e) {}
        }
    }];
    
    // 监控 MainVC 的 state
    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) {
        Class mainVCClass = objc_getClass("ViewController");
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            UIViewController *root = window.rootViewController;
            if ([root isKindOfClass:mainVCClass]) {
                @try {
                    static NSInteger lastState = -999;
                    id val = [root valueForKey:@"state"];
                    NSInteger state = [val integerValue];
                    if (state != lastState) {
                        LOG(@"🔔 [MainVC] state 变化: %ld -> %ld", (long)lastState, (long)state);
                        snapshotProperties(root, [NSString stringWithFormat:@"MainVC(state=%ld)", (long)state]);
                        lastState = state;
                    }
                } @catch (NSException *e) {}
                break;
            }
        }
    }];
}

// ============================================================
// Hook 入口（只记录，不拦截）
// ============================================================
static void hookActivationVC(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
    LOG(@"🎣 记录: %s", class_getName(cls));
    
    Method m;
    
    // viewDidLoad：记录属性，保存弱引用
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [ActVC] viewDidLoad");
            g_actVC = self;
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
            snapshotProperties(self, @"ActVC(viewDidLoad)");
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
        LOG(@"  ✅ viewDidLoad");
    }
    
    // onTapVerify：记录但不拦截
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [ActVC] onTapVerify 被点击");
            snapshotProperties(self, @"ActVC(点击验证前)");
            ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
            LOG(@"🎯 [ActVC] onTapVerify 执行完毕");
            snapshotProperties(self, @"ActVC(点击验证后)");
        });
        class_replaceMethod(cls, @selector(onTapVerify), newIMP, typeEnc);
        LOG(@"  ✅ onTapVerify");
    }
    
    // showError:：记录
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
            LOG(@"🛡️ [ActVC] showError: %@", msg);
            snapshotProperties(self, @"ActVC(showError)");
            ((void (*)(id, SEL, NSString*))orig)(self, @selector(showError:), msg);
        });
        class_replaceMethod(cls, @selector(showError:), newIMP, typeEnc);
        LOG(@"  ✅ showError:");
    }
    
    // showSuccess:completion:：记录
    m = class_getInstanceMethod(cls, @selector(showSuccess:completion:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, id expire, id completion) {
            LOG(@"🎉 [ActVC] showSuccess:completion: 被调用");
            LOG(@"   expire = %@", expire);
            LOG(@"   completion 类 = %@", NSStringFromClass([completion class]));
            snapshotProperties(self, @"ActVC(showSuccess前)");
            ((void (*)(id, SEL, id, id))orig)(self, @selector(showSuccess:completion:), expire, completion);
            LOG(@"🎉 [ActVC] showSuccess:completion: 执行完毕");
            snapshotProperties(self, @"ActVC(showSuccess后)");
        });
        class_replaceMethod(cls, @selector(showSuccess:completion:), newIMP, typeEnc);
        LOG(@"  ✅ showSuccess:completion:");
    }
    
    // buildSuccessViewWithExpire:：记录
    m = class_getInstanceMethod(cls, @selector(buildSuccessViewWithExpire:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, id expire) {
            LOG(@"🎉 [ActVC] buildSuccessViewWithExpire: %@", expire);
            ((void (*)(id, SEL, id))orig)(self, @selector(buildSuccessViewWithExpire:), expire);
        });
        class_replaceMethod(cls, @selector(buildSuccessViewWithExpire:), newIMP, typeEnc);
        LOG(@"  ✅ buildSuccessViewWithExpire:");
    }
    
    // setupAfterActivation：记录
    m = class_getInstanceMethod(cls, @selector(setupAfterActivation));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎉 [ActVC] setupAfterActivation 被调用");
            ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
        });
        class_replaceMethod(cls, @selector(setupAfterActivation), newIMP, typeEnc);
        LOG(@"  ✅ setupAfterActivation");
    }
    
    // 记录所有其他方法
    hookAndLogAllMethods(cls, @"ActVC");
}

static void hookViewController(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 ViewController"); return; }
    LOG(@"🎣 记录 MainVC: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [MainVC] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
            snapshotProperties(self, @"MainVC(viewDidLoad)");
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
        LOG(@"  ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewWillAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [MainVC] viewWillAppear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewWillAppear:), animated);
            snapshotProperties(self, @"MainVC(viewWillAppear)");
        });
        class_replaceMethod(cls, @selector(viewWillAppear:), newIMP, typeEnc);
        LOG(@"  ✅ viewWillAppear:");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [MainVC] viewDidAppear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
            snapshotProperties(self, @"MainVC(viewDidAppear)");
        });
        class_replaceMethod(cls, @selector(viewDidAppear:), newIMP, typeEnc);
        LOG(@"  ✅ viewDidAppear:");
    }
    
    // 记录所有其他方法
    hookAndLogAllMethods(cls, @"MainVC");
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunRec] 真卡密记录版已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        recordNetwork();
        
        Class vcClass = objc_getClass("WWWActivationViewController");
        if (vcClass) hookActivationVC(vcClass);
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        
        startMonitoring();
        
        LOG(@"🚀 记录系统已启动");
        LOG(@"📋 操作：输入真卡密 → 点验证 → 等进入主页面 → 点复制发给我");
        LOG(@"⚠️ 注意：此版本不 bypass，正常走验证流程");
    });
}
