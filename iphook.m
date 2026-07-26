//
//  KFun 全面诊断 Tweak v4 —— 融合版
//  基于用户原版安全框架，保留最大诊断能力
//  原则：① 不在 +load 里 hook  ② 延迟到 App 启动后  ③ 每个操作加 try-catch
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;

static void addLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[IPH] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            NSString *text = g_logView.text;
            NSString *time = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
            NSString *line = [NSString stringWithFormat:@"[%@] %@", time, msg];
            NSString *newText = text.length > 0 ? [NSString stringWithFormat:@"%@\n%@", text, line] : line;
            if (newText.length > 10000) newText = [newText substringFromIndex:newText.length - 10000];
            g_logView.text = newText;
            [g_logView scrollRangeToVisible:NSMakeRange(newText.length - 1, 1)];
        }
    });
}

// ============================================================
// 🪟 悬浮窗（用户原版，安全）
// ============================================================
@interface LogDragHandler : NSObject
@end
@implementation LogDragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view.superview;
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview];
}
- (void)copyLog:(id)sender {
    if (g_logView) {
        UIPasteboard.generalPasteboard.string = g_logView.text;
        addLog(@"📋 日志已复制到剪贴板");
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
        if (!keyWindow) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ setupLogWindow(); });
            return;
        }

        CGFloat w = 340, h = 320;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(10, 120, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor greenColor].CGColor;
        g_logContainer.layer.borderWidth = 1.5;

        UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 30)];
        titleBar.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
        [g_logContainer addSubview:titleBar];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, w-70, 22)];
        title.text = @"🔍 KFun 诊断v4 (拖动标题栏)";
        title.textColor = [UIColor greenColor];
        title.font = [UIFont boldSystemFontOfSize:11];
        [titleBar addSubview:title];

        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w-60, 4, 55, 22);
        [copyBtn setTitle:@"📋复制" forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont systemFontOfSize:10];
        [copyBtn setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
        g_dragHandler = [[LogDragHandler alloc] init];
        [copyBtn addTarget:g_dragHandler action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [titleBar addSubview:copyBtn];

        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 32, w-4, h-34)];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:9];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = YES;
        g_logView.text = @"[系统] KFun诊断v4已启动\n💡 长按日志可全选复制\n💡 拖动标题栏可移动窗口\n";
        [g_logContainer addSubview:g_logView];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_dragHandler action:@selector(handlePan:)];
        [titleBar addGestureRecognizer:pan];

        [keyWindow addSubview:g_logContainer];
        addLog(@"✅ 悬浮窗已创建");
    });
}

// ============================================================
// 🔍 安全描述工具
// ============================================================
static NSString *safeDesc(id obj) {
    if (!obj) return @"nil";
    @try {
        if ([obj isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"\"%@\"", obj];
        if ([obj isKindOfClass:[NSArray class]]) return [NSString stringWithFormat:@"NSArray(count=%lu)", (unsigned long)[(NSArray*)obj count]];
        if ([obj isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"NSDictionary(count=%lu keys=%@)", (unsigned long)[(NSDictionary*)obj count], [(NSDictionary*)obj allKeys]];
        if ([obj isKindOfClass:[NSData class]]) {
            NSData *d = obj;
            if (d.length < 256) {
                NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                if (s) return [NSString stringWithFormat:@"NSData(len=%lu,utf8=%@)", (unsigned long)d.length, s];
            }
            return [NSString stringWithFormat:@"NSData(len=%lu)", (unsigned long)d.length];
        }
        return [obj description];
    } @catch (NSException *e) { return @"[desc_error]"; }
}

// ============================================================
// 🖱️ 按钮点击记录（用户原版 C函数方式，安全）
// ============================================================
static void (*orig_controlSendAction)(id, SEL, SEL, id, id);
static void swizzled_controlSendAction(id self, SEL _cmd, SEL action, id target, UIEvent *event) {
    if ([self isKindOfClass:[UIButton class]]) {
        addLog(@"🖱️ 按钮点击: %@ -> %@.%@", NSStringFromClass([self class]), target ? NSStringFromClass([target class]) : @"nil", NSStringFromSelector(action));
        NSString *tt = [((UIButton*)self) titleForState:UIControlStateNormal];
        if (tt.length) addLog(@"   └─ title=\"%@\"", tt);
    }
    orig_controlSendAction(self, _cmd, action, target, event);
}

// ============================================================
// 🔍 新增诊断：UIViewController viewDidLoad（只打印类名，不 dump）
// ============================================================
static void (*orig_vc_viewDidLoad)(id, SEL);
static void diag_vc_viewDidLoad(id self, SEL _cmd) {
    addLog(@"📱 [VC] viewDidLoad → %@", NSStringFromClass([self class]));
    orig_vc_viewDidLoad(self, _cmd);
}

// ============================================================
// 🔍 新增诊断：UINavigationController push
// ============================================================
static void (*orig_nav_push)(id, SEL, id, BOOL);
static void diag_nav_push(id self, SEL _cmd, id vc, BOOL animated) {
    addLog(@"📱 [NAV] push %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc class]));
    orig_nav_push(self, _cmd, vc, animated);
}

// ============================================================
// 🔍 新增诊断：UIViewController present
// ============================================================
static void (*orig_vc_present)(id, SEL, id, BOOL, id);
static void diag_vc_present(id self, SEL _cmd, id vc, BOOL animated, id completion) {
    addLog(@"📱 [VC] present %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc class]));
    orig_vc_present(self, _cmd, vc, animated, completion);
}

// ============================================================
// 🔍 新增诊断：UITableView reloadData
// ============================================================
static void (*orig_tv_reload)(id, SEL);
static void diag_tv_reload(id self, SEL _cmd) {
    @try {
        NSInteger sec = [(UITableView*)self numberOfSections];
        NSInteger rows = 0;
        for (NSInteger i = 0; i < sec; i++) rows += [(UITableView*)self numberOfRowsInSection:i];
        addLog(@"📋 [TV] reloadData %@ | sections=%ld | totalRows=%ld", NSStringFromClass([self class]), (long)sec, (long)rows);
    } @catch (NSException *e) { addLog(@"📋 [TV] reloadData %@ | [计数异常]", NSStringFromClass([self class])); }
    orig_tv_reload(self, _cmd);
}

// ============================================================
// 🔍 新增诊断：NSUserDefaults
// ============================================================
static id (*orig_ud_get)(id, SEL, id);
static id diag_ud_get(id self, SEL _cmd, id key) {
    id v = orig_ud_get(self, _cmd, key);
    addLog(@"💾 [UD] read %@ = %@", key, safeDesc(v));
    return v;
}
static void (*orig_ud_set)(id, SEL, id, id);
static void diag_ud_set(id self, SEL _cmd, id v, id key) {
    addLog(@"💾 [UD] write %@ = %@", key, safeDesc(v));
    orig_ud_set(self, _cmd, v, key);
}

// ============================================================
// 🔍 新增诊断：NSData writeToFile
// ============================================================
static BOOL (*orig_data_wf)(id, SEL, id, BOOL);
static BOOL diag_data_wf(id self, SEL _cmd, id path, BOOL atom) {
    addLog(@"💾 [FILE] write %@ | len=%lu", path, (unsigned long)[(NSData*)self length]);
    return orig_data_wf(self, _cmd, path, atom);
}

// ============================================================
// 🔍 新增诊断：NSString writeToFile
// ============================================================
static BOOL (*orig_str_wf)(id, SEL, id, BOOL, NSUInteger, id);
static BOOL diag_str_wf(id self, SEL _cmd, id path, BOOL atom, NSUInteger enc, id err) {
    addLog(@"💾 [FILE] writeStr %@ | content=%@", path, self);
    return orig_str_wf(self, _cmd, path, atom, enc, err);
}

// ============================================================
// 🔍 新增诊断：NSURLSession 网络
// ============================================================
static NSURLSessionDataTask* (*orig_session_url)(id, SEL, id, id);
static NSURLSessionDataTask* diag_session_url(id self, SEL _cmd, id url, id cb) {
    addLog(@"🌐 [NET] GET %@", [url absoluteString]);
    void (^origCb)(NSData*,NSURLResponse*,NSError*) = cb;
    void (^wrap)(NSData*,NSURLResponse*,NSError*) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        @try {
            NSHTTPURLResponse *h = [r isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)r : nil;
            addLog(@"🌐 [NET] RESP %@ | status=%ld | len=%lu | err=%@", [url absoluteString], (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0), e?e.localizedDescription:@"none");
            if (d && d.length < 512) {
                NSString *b = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                if (b) addLog(@"🌐 [NET] BODY: %@", b);
            }
        } @catch (NSException *ex) {}
        if (origCb) origCb(d, r, e);
    };
    return orig_session_url(self, _cmd, url, wrap);
}

static NSURLSessionDataTask* (*orig_session_req)(id, SEL, id, id);
static NSURLSessionDataTask* diag_session_req(id self, SEL _cmd, id req, id cb) {
    NSURLRequest *r = req;
    addLog(@"🌐 [NET] %@ %@ | hdr=%@ | bodyLen=%lu", r.HTTPMethod, r.URL.absoluteString, r.allHTTPHeaderFields, (unsigned long)(r.HTTPBody?r.HTTPBody.length:0));
    if (r.HTTPBody && r.HTTPBody.length < 256) {
        NSString *b = [[NSString alloc] initWithData:r.HTTPBody encoding:NSUTF8StringEncoding];
        if (b) addLog(@"🌐 [NET] REQBODY: %@", b);
    }
    void (^origCb)(NSData*,NSURLResponse*,NSError*) = cb;
    void (^wrap)(NSData*,NSURLResponse*,NSError*) = ^(NSData *d, NSURLResponse *resp, NSError *e) {
        @try {
            NSHTTPURLResponse *h = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)resp : nil;
            addLog(@"🌐 [NET] RESP %@ | status=%ld | len=%lu", r.URL.absoluteString, (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0));
            if (d && d.length < 512) {
                NSString *b = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                if (b) addLog(@"🌐 [NET] BODY: %@", b);
            }
        } @catch (NSException *ex) {}
        if (origCb) origCb(d, resp, e);
    };
    return orig_session_req(self, _cmd, req, wrap);
}

// ============================================================
// 🔍 安全安装所有诊断 hook（延迟执行，不在 +load）
// ============================================================
static void installDiagnosticHooks() {
    addLog(@"🔧 安装诊断 hook...");

    // 1. UIViewController viewDidLoad
    @try {
        Method m = class_getInstanceMethod([UIViewController class], @selector(viewDidLoad));
        if (m) {
            orig_vc_viewDidLoad = (void (*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m, (IMP)diag_vc_viewDidLoad);
            addLog(@"  ✅ UIViewController viewDidLoad");
        }
    } @catch (NSException *e) { addLog(@"  ❌ VC viewDidLoad: %@", e.reason); }

    // 2. UINavigationController push
    @try {
        Method m = class_getInstanceMethod([UINavigationController class], @selector(pushViewController:animated:));
        if (m) {
            orig_nav_push = (void (*)(id, SEL, id, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)diag_nav_push);
            addLog(@"  ✅ UINavigationController push");
        }
    } @catch (NSException *e) { addLog(@"  ❌ NAV push: %@", e.reason); }

    // 3. UIViewController present
    @try {
        Method m = class_getInstanceMethod([UIViewController class], @selector(presentViewController:animated:completion:));
        if (m) {
            orig_vc_present = (void (*)(id, SEL, id, BOOL, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)diag_vc_present);
            addLog(@"  ✅ UIViewController present");
        }
    } @catch (NSException *e) { addLog(@"  ❌ VC present: %@", e.reason); }

    // 4. UITableView reloadData
    @try {
        Method m = class_getInstanceMethod([UITableView class], @selector(reloadData));
        if (m) {
            orig_tv_reload = (void (*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m, (IMP)diag_tv_reload);
            addLog(@"  ✅ UITableView reloadData");
        }
    } @catch (NSException *e) { addLog(@"  ❌ TV reloadData: %@", e.reason); }

    // 5. NSUserDefaults
    @try {
        Method m1 = class_getInstanceMethod([NSUserDefaults class], @selector(objectForKey:));
        if (m1) { orig_ud_get = (id (*)(id, SEL, id))method_getImplementation(m1); method_setImplementation(m1, (IMP)diag_ud_get); }
        Method m2 = class_getInstanceMethod([NSUserDefaults class], @selector(setObject:forKey:));
        if (m2) { orig_ud_set = (void (*)(id, SEL, id, id))method_getImplementation(m2); method_setImplementation(m2, (IMP)diag_ud_set); }
        addLog(@"  ✅ NSUserDefaults");
    } @catch (NSException *e) { addLog(@"  ❌ NSUserDefaults: %@", e.reason); }

    // 6. NSData writeToFile
    @try {
        Method m = class_getInstanceMethod([NSData class], @selector(writeToFile:atomically:));
        if (m) { orig_data_wf = (BOOL (*)(id, SEL, id, BOOL))method_getImplementation(m); method_setImplementation(m, (IMP)diag_data_wf); }
        addLog(@"  ✅ NSData writeToFile");
    } @catch (NSException *e) { addLog(@"  ❌ NSData write: %@", e.reason); }

    // 7. NSString writeToFile
    @try {
        Method m = class_getInstanceMethod([NSString class], @selector(writeToFile:atomically:encoding:error:));
        if (m) { orig_str_wf = (BOOL (*)(id, SEL, id, BOOL, NSUInteger, id))method_getImplementation(m); method_setImplementation(m, (IMP)diag_str_wf); }
        addLog(@"  ✅ NSString writeToFile");
    } @catch (NSException *e) { addLog(@"  ❌ NSString write: %@", e.reason); }

    // 8. NSURLSession
    @try {
        Method m1 = class_getInstanceMethod([NSURLSession class], @selector(dataTaskWithURL:completionHandler:));
        if (m1) { orig_session_url = (NSURLSessionDataTask* (*)(id, SEL, id, id))method_getImplementation(m1); method_setImplementation(m1, (IMP)diag_session_url); }
        Method m2 = class_getInstanceMethod([NSURLSession class], @selector(dataTaskWithRequest:completionHandler:));
        if (m2) { orig_session_req = (NSURLSessionDataTask* (*)(id, SEL, id, id))method_getImplementation(m2); method_setImplementation(m2, (IMP)diag_session_req); }
        addLog(@"  ✅ NSURLSession");
    } @catch (NSException *e) { addLog(@"  ❌ NSURLSession: %@", e.reason); }

    addLog(@"🔧 诊断 hook 安装完成");
}

// ============================================================
// 🚀 Bypass 核心（用户原版）
// ============================================================
static void doBypass(id target) {
    addLog(@"🚀 开始 Bypass...");

    @try {
        if ([target isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)target;
            for (UIView *v in vc.view.subviews) {
                if ([v isKindOfClass:[UIActivityIndicatorView class]]) {
                    [(UIActivityIndicatorView *)v stopAnimating];
                    v.hidden = YES;
                }
            }
        }
    } @catch (NSException *e) {}
    addLog(@"✅ 转圈已停止");

    @try {
        id mask = [target valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            addLog(@"✅ authMaskView 已移除");
        }
    } @catch (NSException *e) {}

    @try {
        if ([target respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            [target performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
            addLog(@"✅ buildSuccessViewWithExpire: 已调用");
        } else {
            addLog(@"⚠️ 无 buildSuccessViewWithExpire:");
        }
    } @catch (NSException *e) {
        addLog(@"❌ buildSuccessViewWithExpire: 失败: %@", e.reason);
    }

    @try {
        if ([target respondsToSelector:@selector(setupAfterActivation)]) {
            [target performSelector:@selector(setupAfterActivation)];
            addLog(@"✅ setupAfterActivation 已调用");
        } else {
            addLog(@"⚠️ 无 setupAfterActivation");
        }
    } @catch (NSException *e) {
        addLog(@"❌ setupAfterActivation 失败: %@", e.reason);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([target isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)target;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:nil];
                    addLog(@"✅ dismiss 验证弹窗");
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// 🎣 Hook 验证类（用户原版）
// ============================================================
static void hookActivationClass(Class cls) {
    if (!cls) return;
    addLog(@"🎣 Hook 类: %s", class_getName(cls));
    Method m;

    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            addLog(@"🎯 viewDidLoad 触发");
            struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&super, @selector(viewDidLoad));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ doBypass(self); });
        }));
        addLog(@"  ✅ viewDidLoad");
    }

    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            addLog(@"🎯 onTapVerify 被点击");
            doBypass(self);
        }));
        addLog(@"  ✅ onTapVerify");
    } else { addLog(@"  ⚠️ 无 onTapVerify"); }

    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *code, id completion) {
            addLog(@"🎯 activateCode: 被调用, code=%@, completion=%@", code, safeDesc(completion));
            doBypass(self);
        }));
        addLog(@"  ✅ activateCode:completion:");
    }

    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *msg) {
            addLog(@"🛡️ showError 拦截: %@", msg);
            doBypass(self);
        }));
        addLog(@"  ✅ showError:");
    } else { addLog(@"  ⚠️ 无 showError:"); }

    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) { return YES; }));
        addLog(@"  ✅ isActivated -> YES");
    }
}

static void scanAndHookActivation() {
    addLog(@"🔍 扫描验证类...");
    Class cls = objc_getClass("WWWActivationViewController");
    if (!cls) cls = objc_getClass("WWWActivation");
    if (cls) hookActivationClass(cls);
    else addLog(@"❌ 未找到验证类");
}

// ============================================================
// 🔍 轮询检测当前 VC（用户原版增强）
// ============================================================
static UIViewController *getTopVC() {
    @try {
        UIWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)scene).activationState == UISceneActivationStateForegroundActive) {
                    if (((UIWindowScene *)scene).windows.count > 0) { window = ((UIWindowScene *)scene).windows.firstObject; break; }
                }
            }
        }
        if (!window) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            window = [UIApplication sharedApplication].keyWindow;
            if (!window && [UIApplication sharedApplication].windows.count > 0) window = [UIApplication sharedApplication].windows[0];
            #pragma clang diagnostic pop
        }
        if (!window) return nil;
        UIViewController *vc = window.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        return vc;
    } @catch (NSException *e) { return nil; }
}

static void detectCurrentVC() {
    @try {
        UIViewController *vc = getTopVC();
        if (!vc) { addLog(@"⚠️ 未找到当前 VC"); return; }
        NSString *clsName = NSStringFromClass([vc class]);
        addLog(@"📍 当前界面: %@", clsName);

        NSArray *keys = @[@"authMaskView", @"codeField", @"verifyButton", @"errorLabel", @"successView", @"spinner", @"tableView", @"values", @"host", @"dataText"];
        for (NSString *key in keys) {
            id val = nil;
            @try { val = [vc valueForKey:key]; } @catch (NSException *e) {}
            if (val) addLog(@"  📌 %@: %@", key, safeDesc(val));
        }
    } @catch (NSException *e) { addLog(@"❌ detectCurrentVC 异常: %@", e.reason); }
}

static void startPolling() {
    [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *timer) {
        @try { detectCurrentVC(); } @catch (NSException *e) { addLog(@"❌ 轮询异常: %@", e.reason); }
    }];
    addLog(@"🔄 轮询已启动 (每5秒检测当前VC)");
}

// ============================================================
// 初始化（用户原版时机 + 新增诊断 hook）
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[IPH] KFun 诊断v4 已加载");
    NSLog(@"========================================");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        setupLogWindow();

        // 用户原版：UIControl sendAction
        Class controlClass = [UIControl class];
        Method m = class_getInstanceMethod(controlClass, @selector(sendAction:to:forEvent:));
        if (m) {
            orig_controlSendAction = (void (*)(id, SEL, SEL, id, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)swizzled_controlSendAction);
            addLog(@"✅ UIControl sendAction 已 hook");
        }

        // 用户原版：扫描并 hook 验证类
        scanAndHookActivation();

        // 用户原版：轮询
        startPolling();

        // 新增：延迟 1.5 秒后安装其他诊断 hook（确保 App 启动完成）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            installDiagnosticHooks();
        });

        addLog(@"🚀 初始化完成");
        addLog(@"💡 操作：展开悬浮窗 → 输入任意卡密 → 点验证 → 看日志");
    });
}
