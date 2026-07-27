//
//  iphook.m - KFun 真卡密纯净记录版 v5
//  原则：只读、只记、不改。所有参数/回调直接透传，绝不替换 block。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunRec] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 80000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 80000)];
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
        title.text = @"🔍 KFun 真卡密记录 (拖动)";
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

// ============================================================
// 快照工具
// ============================================================
static void snapProps(id obj, NSString *label) {
    if (!obj) return;
    LOG(@"📸 [%@] props begin", label);
    unsigned int c = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &c);
    for (unsigned int i = 0; i < c; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            id val = [obj valueForKey:name];
            NSString *d = val ? [val description] : @"nil";
            if (d.length > 100) d = [d substringToIndex:100];
            LOG(@"   %@=%@", name, d);
        } @catch (NSException *e) {}
    }
    if (props) free(props);
    LOG(@"📸 [%@] props end", label);
}

static void snapIvars(id obj, NSString *label) {
    if (!obj) return;
    LOG(@"📦 [%@] ivars begin", label);
    unsigned int c = 0;
    Ivar *ivars = class_copyIvarList(object_getClass(obj), &c);
    for (unsigned int i = 0; i < c; i++) {
        NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i])];
        @try {
            id val = object_getIvar(obj, ivars[i]);
            NSString *d = val ? [val description] : @"nil";
            if (d.length > 100) d = [d substringToIndex:100];
            LOG(@"   %@=%@", name, d);
        } @catch (NSException *e) {}
    }
    if (ivars) free(ivars);
    LOG(@"📦 [%@] ivars end", label);
}

static void dumpViews(UIView *v, int depth) {
    if (!v || depth > 5) return;
    NSString *ind = [@"" stringByPaddingToLength:depth*2 withString:@"  " startingAtIndex:0];
    LOG(@"%@%@%@ frame=%@ h=%d a=%.1f", ind, v.hidden?@"[H]":@"", NSStringFromClass([v class]), NSStringFromCGRect(v.frame), (int)v.hidden, v.alpha);
    for (UIView *sub in v.subviews) dumpViews(sub, depth+1);
}

static void dumpWin(NSString *label) {
    LOG(@"🪟 [%@] begin", label);
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray *wins = [UIApplication sharedApplication].windows;
    #pragma clang diagnostic pop
    for (UIWindow *w in wins) {
        LOG(@"  Win %@ root=%@ hidden=%d", NSStringFromClass([w class]), NSStringFromClass([w.rootViewController class]), (int)w.hidden);
        if (w.rootViewController) dumpViews(w.rootViewController.view, 1);
    }
    LOG(@"🪟 [%@] end", label);
}

// ============================================================
// 🎣 安全 Hook 宏：入口记录，出口记录，中间绝对透传
// ============================================================
#define SAFE_HOOK_0(cls, selName, logPrefix) \
do { \
    Method m = class_getInstanceMethod(cls, @selector(selName)); \
    if (m) { \
        IMP orig = method_getImplementation(m); \
        const char *te = method_getTypeEncoding(m); \
        IMP imp = imp_implementationWithBlock(^(id self) { \
            LOG(@"%@ " #selName " 入口", logPrefix); \
            snapIvars(self, @"" #selName "_入口"); \
            ((void (*)(id, SEL))orig)(self, @selector(selName)); \
            LOG(@"%@ " #selName " 出口", logPrefix); \
            snapIvars(self, @"" #selName "_出口"); \
        }); \
        class_replaceMethod(cls, @selector(selName), imp, te); \
        LOG(@"  ✅ " #selName); \
    } \
} while(0)

#define SAFE_HOOK_1(cls, selName, type1, logPrefix) \
do { \
    Method m = class_getInstanceMethod(cls, @selector(selName:)); \
    if (m) { \
        IMP orig = method_getImplementation(m); \
        const char *te = method_getTypeEncoding(m); \
        IMP imp = imp_implementationWithBlock(^(id self, type1 arg1) { \
            LOG(@"%@ " #selName ":%@ 入口", logPrefix, arg1 ? [NSString stringWithFormat:@"%@", arg1] : @"nil"); \
            snapIvars(self, @"" #selName "_入口"); \
            ((void (*)(id, SEL, type1))orig)(self, @selector(selName:), arg1); \
            LOG(@"%@ " #selName ": 出口", logPrefix); \
            snapIvars(self, @"" #selName "_出口"); \
        }); \
        class_replaceMethod(cls, @selector(selName:), imp, te); \
        LOG(@"  ✅ " #selName ":"); \
    } \
} while(0)

#define SAFE_HOOK_2(cls, selName, type1, type2, logPrefix) \
do { \
    Method m = class_getInstanceMethod(cls, @selector(selName:selName:)); \
    if (m) { \
        IMP orig = method_getImplementation(m); \
        const char *te = method_getTypeEncoding(m); \
        IMP imp = imp_implementationWithBlock(^(id self, type1 arg1, type2 arg2) { \
            NSString *a1 = arg1 ? [NSString stringWithFormat:@"%@", arg1] : @"nil"; \
            NSString *a2 = arg2 ? [NSString stringWithFormat:@"%@", arg2] : @"nil"; \
            if (a1.length > 80) a1 = [a1 substringToIndex:80]; \
            if (a2.length > 80) a2 = [a2 substringToIndex:80]; \
            LOG(@"%@ " #selName ":%@ %@ 入口", logPrefix, a1, a2); \
            snapIvars(self, @"" #selName "_入口"); \
            ((void (*)(id, SEL, type1, type2))orig)(self, @selector(selName:selName:), arg1, arg2); \
            LOG(@"%@ " #selName ": 出口", logPrefix); \
            snapIvars(self, @"" #selName "_出口"); \
        }); \
        class_replaceMethod(cls, @selector(selName:selName:), imp, te); \
        LOG(@"  ✅ " #selName ":"); \
    } \
} while(0)

// ============================================================
// 🎣 网络记录（只记录 URL，不 wrap block）
// ============================================================
static void hookNetwork() {
    Class cls = [NSURLSession class];
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP imp = imp_implementationWithBlock(^(id self, NSURLRequest *req, id completion) {
            NSString *body = nil;
            if (req.HTTPBody && req.HTTPBody.length < 2000) {
                body = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
            }
            LOG(@"🌐 REQ %@ %@ body=%@", req.HTTPMethod, req.URL.absoluteString, body ? body : @"nil");
            // 直接透传 completion，绝不 wrap
            id ret = ((id (*)(id, SEL, NSURLRequest*, id))orig)(self, @selector(dataTaskWithRequest:completionHandler:), req, completion);
            return ret;
        });
        class_replaceMethod(cls, @selector(dataTaskWithRequest:completionHandler:), imp, te);
        LOG(@"✅ 网络已 Hook");
    }
}

// ============================================================
// 🎣 主 Hook
// ============================================================
static void hookAll() {
    Class actCls = objc_getClass(@"WWWActivation");
    Class actVC = objc_getClass(@"WWWActivationViewController");
    Class mainVC = objc_getClass(@"ViewController");

    if (actCls) {
        LOG(@"🎣 Hook WWWActivation");
        // activateCode:completion: —— 只记录，透传 completion
        Method m = class_getInstanceMethod(actCls, @selector(activateCode:completion:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP imp = imp_implementationWithBlock(^(id self, NSString *code, id completion) {
                LOG(@"🎣 activateCode:%@ completion=%@", code, completion ? @"有" : @"nil");
                snapIvars(self, @"WWWActivation_activateCode入口");
                // 直接透传
                id ret = ((id (*)(id, SEL, NSString*, id))orig)(self, @selector(activateCode:completion:), code, completion);
                LOG(@"🎣 activateCode 已返回");
                // 延迟快照
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    snapIvars(self, @"WWWActivation_activateCode+0.5s");
                });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    snapIvars(self, @"WWWActivation_activateCode+1.5s");
                });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    snapIvars(self, @"WWWActivation_activateCode+3.0s");
                });
                return ret;
            });
            class_replaceMethod(actCls, @selector(activateCode:completion:), imp, te);
            LOG(@"  ✅ activateCode:completion:");
        }

        SAFE_HOOK_0(actCls, setupAfterActivation, @"🎣");

        // activationStampPath —— 记录返回值
        Method m2 = class_getInstanceMethod(actCls, @selector(activationStampPath));
        if (m2) {
            IMP orig = method_getImplementation(m2);
            const char *te = method_getTypeEncoding(m2);
            IMP imp = imp_implementationWithBlock(^(id self) {
                NSString *path = ((NSString* (*)(id, SEL))orig)(self, @selector(activationStampPath));
                LOG(@"🎣 activationStampPath=%@", path);
                return path;
            });
            class_replaceMethod(actCls, @selector(activationStampPath), imp, te);
            LOG(@"  ✅ activationStampPath");
        }
    }

    if (actVC) {
        LOG(@"🎣 Hook ActVC");
        SAFE_HOOK_0(actVC, viewDidLoad, @"🎯");

        // onTapVerify
        Method m = class_getInstanceMethod(actVC, @selector(onTapVerify));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP imp = imp_implementationWithBlock(^(id self) {
                LOG(@"🎯 onTapVerify 入口");
                snapIvars(self, @"ActVC_onTapVerify入口");
                ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
                LOG(@"🎯 onTapVerify 出口");
                snapIvars(self, @"ActVC_onTapVerify出口");
            });
            class_replaceMethod(actVC, @selector(onTapVerify), imp, te);
            LOG(@"  ✅ onTapVerify");
        }

        SAFE_HOOK_1(actVC, showError, NSString*, @"🛡️");

        // showSuccess:completion: —— 只记录，透传 completion
        Method m2 = class_getInstanceMethod(actVC, @selector(showSuccess:completion:));
        if (m2) {
            IMP orig = method_getImplementation(m2);
            const char *te = method_getTypeEncoding(m2);
            IMP imp = imp_implementationWithBlock(^(id self, id expire, id completion) {
                LOG(@"🎉 showSuccess:%@ completion=%@", expire, completion ? @"有" : @"nil");
                snapIvars(self, @"ActVC_showSuccess入口");
                // 直接透传
                ((void (*)(id, SEL, id, id))orig)(self, @selector(showSuccess:completion:), expire, completion);
                LOG(@"🎉 showSuccess 出口");
                snapIvars(self, @"ActVC_showSuccess出口");
            });
            class_replaceMethod(actVC, @selector(showSuccess:completion:), imp, te);
            LOG(@"  ✅ showSuccess:completion:");
        }

        SAFE_HOOK_1(actVC, buildSuccessViewWithExpire, id, @"🎉");
        SAFE_HOOK_0(actVC, setupAfterActivation, @"🎉");

        // dismissViewControllerAnimated:completion: —— 只记录，透传 completion
        Method m3 = class_getInstanceMethod(actVC, @selector(dismissViewControllerAnimated:completion:));
        if (m3) {
            IMP orig = method_getImplementation(m3);
            const char *te = method_getTypeEncoding(m3);
            IMP imp = imp_implementationWithBlock(^(id self, BOOL anim, id completion) {
                LOG(@"🚪 dismiss animated=%d completion=%@", (int)anim, completion ? @"有" : @"nil");
                dumpWin(@"dismiss前");
                // 直接透传
                ((void (*)(id, SEL, BOOL, id))orig)(self, @selector(dismissViewControllerAnimated:completion:), anim, completion);
                LOG(@"🚪 dismiss 已调用");
                dumpWin(@"dismiss后");
            });
            class_replaceMethod(actVC, @selector(dismissViewControllerAnimated:completion:), imp, te);
            LOG(@"  ✅ dismissViewControllerAnimated:completion:");
        }
    }

    if (mainVC) {
        LOG(@"🎣 Hook MainVC");

        Method m1 = class_getInstanceMethod(mainVC, @selector(viewDidLoad));
        if (m1) {
            IMP orig = method_getImplementation(m1);
            const char *te = method_getTypeEncoding(m1);
            IMP imp = imp_implementationWithBlock(^(id self) {
                LOG(@"🎯 MainVC viewDidLoad");
                ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
                snapIvars(self, @"MainVC_viewDidLoad");
                dumpViews(((UIViewController*)self).view, 0);
            });
            class_replaceMethod(mainVC, @selector(viewDidLoad), imp, te);
            LOG(@"  ✅ viewDidLoad");
        }

        Method m2 = class_getInstanceMethod(mainVC, @selector(viewDidAppear:));
        if (m2) {
            IMP orig = method_getImplementation(m2);
            const char *te = method_getTypeEncoding(m2);
            IMP imp = imp_implementationWithBlock(^(id self, BOOL anim) {
                LOG(@"🎯 MainVC viewDidAppear");
                ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), anim);
                snapIvars(self, @"MainVC_viewDidAppear");
                dumpViews(((UIViewController*)self).view, 0);

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    LOG(@"🎯 MainVC +0.1s");
                    dumpViews(((UIViewController*)self).view, 0);
                });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    LOG(@"🎯 MainVC +0.5s");
                    dumpViews(((UIViewController*)self).view, 0);
                });
            });
            class_replaceMethod(mainVC, @selector(viewDidAppear:), imp, te);
            LOG(@"  ✅ viewDidAppear:");
        }
    }
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunRec] 真卡密纯净记录版 v5 已加载");
    NSLog(@"========================================");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        hookNetwork();
        hookAll();
        LOG(@"🚀 记录系统已启动");
        LOG(@"📋 操作：输入真卡密 → 点验证 → 等主页面内容出现 → 点复制");
    });
}
