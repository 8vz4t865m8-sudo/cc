//
//  iphook.m - KFun Bypass 诊断版 (修复编译错误)
//  带悬浮窗日志 + 动态检测
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================
// 🪟 悬浮窗日志系统
// ============================================================
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
            if (newText.length > 5000) {
                newText = [newText substringFromIndex:newText.length - 5000];
            }
            g_logView.text = newText;
            [g_logView scrollRangeToVisible:NSMakeRange(newText.length - 1, 1)];
        }
    });
}

static void setupLogWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        // iOS 13+ 用 connectedScenes
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)scene).activationState == UISceneActivationStateForegroundActive) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    if (ws.windows.count > 0) { keyWindow = ws.windows.firstObject; break; }
                }
            }
        }
        if (!keyWindow) {
            // 回退到旧 API
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
            if (!keyWindow && [UIApplication sharedApplication].windows.count > 0) {
                keyWindow = [UIApplication sharedApplication].windows[0];
            }
            #pragma clang diagnostic pop
        }
        if (!keyWindow) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                setupLogWindow();
            });
            return;
        }
        
        CGFloat w = 320, h = 220;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(10, 80, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        g_logContainer.layer.cornerRadius = 8;
        g_logContainer.layer.borderColor = [UIColor greenColor].CGColor;
        g_logContainer.layer.borderWidth = 1;
        g_logContainer.userInteractionEnabled = YES;
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, w, 20)];
        title.text = @" 🔍 KFun 诊断日志";
        title.textColor = [UIColor greenColor];
        title.font = [UIFont boldSystemFontOfSize:10];
        title.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
        [g_logContainer addSubview:title];
        
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 22, w-4, h-24)];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:9];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = NO;
        g_logView.text = @"[系统] 诊断窗口已启动\n";
        [g_logContainer addSubview:g_logView];
        
        [keyWindow addSubview:g_logContainer];
        addLog(@"✅ 悬浮窗已创建");
    });
}

// ============================================================
// 🔍 动态检测：当前最上层 VC
// ============================================================
static UIViewController *getTopVC() {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)scene).activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.windows.count > 0) { window = ws.windows.firstObject; break; }
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
}

static void detectCurrentVC() {
    UIViewController *vc = getTopVC();
    if (!vc) { addLog(@"⚠️ 未找到当前 VC"); return; }
    
    NSString *clsName = NSStringFromClass([vc class]);
    addLog(@"📱 当前界面: %@", clsName);
    
    NSArray *keys = @[@"authMaskView", @"codeField", @"verifyButton", @"errorLabel", @"successView", @"spinner"];
    for (NSString *key in keys) {
        id val = nil;
        @try { val = [vc valueForKey:key]; } @catch (NSException *e) {}
        if (val) addLog(@"  📌 %@: %@", key, NSStringFromClass([val class]));
    }
    
    __block int btnCount = 0, tfCount = 0, spinnerCount = 0;
    void (^scan)(UIView *) = ^(UIView *view) {
        for (UIView *v in view.subviews) {
            if ([v isKindOfClass:[UIButton class]]) btnCount++;
            if ([v isKindOfClass:[UITextField class]]) tfCount++;
            if ([v isKindOfClass:[UIActivityIndicatorView class]]) {
                if ([(UIActivityIndicatorView *)v isAnimating]) spinnerCount++;
            }
            scan(v);
        }
    };
    scan(vc.view);
    addLog(@"  📊 按钮:%d 输入框:%d 转圈:%d", btnCount, tfCount, spinnerCount);
}

// ============================================================
// 🖱️ 动态检测：按钮点击（只记录，不拦截）
// ============================================================
static void (*orig_controlSendAction)(id, SEL, SEL, id, id);

static void swizzled_controlSendAction(id self, SEL _cmd, SEL action, id target, UIEvent *event) {
    if ([self isKindOfClass:[UIButton class]]) {
        NSString *actionName = NSStringFromSelector(action);
        NSString *targetName = target ? NSStringFromClass([target class]) : @"nil";
        addLog(@"🖱️ 按钮点击: %@ -> %@.%@", NSStringFromClass([self class]), targetName, actionName);
    }
    orig_controlSendAction(self, _cmd, action, target, event);
}

// ============================================================
// 🚀 Bypass 核心
// ============================================================
static void doBypass(id target) {
    addLog(@"🚀 开始 Bypass...");
    
    void (^stopSpinners)(UIView *) = ^(UIView *view) {
        for (UIView *v in view.subviews) {
            if ([v isKindOfClass:[UIActivityIndicatorView class]]) {
                [(UIActivityIndicatorView *)v stopAnimating];
                v.hidden = YES;
            }
            stopSpinners(v);
        }
    };
    if ([target isKindOfClass:[UIViewController class]]) {
        stopSpinners([(UIViewController *)target view]);
    }
    addLog(@"✅ 转圈已停止");
    
    id mask = nil;
    @try { mask = [target valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
    if (mask && [mask isKindOfClass:[UIView class]]) {
        [(UIView *)mask setHidden:YES];
        [(UIView *)mask removeFromSuperview];
        addLog(@"✅ authMaskView 已移除");
    }
    
    if ([target respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
        @try {
            [target performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
            addLog(@"✅ buildSuccessViewWithExpire: 已调用");
        } @catch (NSException *e) {
            addLog(@"❌ buildSuccessViewWithExpire: 失败: %@", e);
        }
    } else {
        addLog(@"⚠️ 无 buildSuccessViewWithExpire:");
    }
    
    if ([target respondsToSelector:@selector(setupAfterActivation)]) {
        @try {
            [target performSelector:@selector(setupAfterActivation)];
            addLog(@"✅ setupAfterActivation 已调用");
        } @catch (NSException *e) {
            addLog(@"❌ setupAfterActivation 失败: %@", e);
        }
    } else {
        addLog(@"⚠️ 无 setupAfterActivation");
    }
    
    if ([target respondsToSelector:@selector(enterMainConsole)]) {
        @try {
            [target performSelector:@selector(enterMainConsole)];
            addLog(@"✅ enterMainConsole 已调用");
        } @catch (NSException *e) {
            addLog(@"❌ enterMainConsole 失败: %@", e);
        }
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
// 🎣 Hook 验证类
// ============================================================
static void hookClass(Class cls) {
    if (!cls) return;
    addLog(@"🎣 Hook 类: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            addLog(@"🎯 viewDidLoad 触发");
            struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&super, @selector(viewDidLoad));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                doBypass(self);
            });
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
    }
    
    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *code, id completion) {
            addLog(@"🎯 activateCode: 被调用, code=%@", code);
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
    }
    
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            return YES;
        }));
        addLog(@"  ✅ isActivated -> YES");
    }
}

static void scanAndHook() {
    addLog(@"🔍 扫描验证类...");
    
    Class cls = objc_getClass("WWWActivation");
    if (!cls) cls = objc_getClass("WWWActivationViewController");
    if (cls) {
        hookClass(cls);
        return;
    }
    
    int num = objc_getClassList(NULL, 0);
    if (num > 0) {
        Class *classes = (Class *)malloc(sizeof(Class) * num);
        objc_getClassList(classes, num);
        for (int i = 0; i < num; i++) {
            if (class_getInstanceMethod(classes[i], @selector(verifyButton)) ||
                class_getInstanceMethod(classes[i], @selector(authMaskView)) ||
                class_getInstanceMethod(classes[i], @selector(onTapVerify))) {
                addLog(@"🔍 扫描到验证类: %s", class_getName(classes[i]));
                hookClass(classes[i]);
                free(classes);
                return;
            }
        }
        free(classes);
    }
    
    addLog(@"⚠️ 未找到验证类，2秒后重试...");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scanAndHook();
    });
}

// ============================================================
// 🔄 定时轮询
// ============================================================
static void startPolling() {
    [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *timer) {
        detectCurrentVC();
        
        UIViewController *vc = getTopVC();
        if (!vc) return;
        
        BOOL hasMask = NO, hasCodeField = NO;
        @try { hasMask = ([vc valueForKey:@"authMaskView"] != nil); } @catch (NSException *e) {}
        @try { hasCodeField = ([vc valueForKey:@"codeField"] != nil); } @catch (NSException *e) {}
        
        if (hasMask || hasCodeField) {
            addLog(@"🤖 自动检测到验证界面，执行 bypass");
            doBypass(vc);
        }
    }];
    addLog(@"🔄 轮询已启动 (每3秒)");
}

// ============================================================
// 初始化
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[IPH] KFun 诊断版已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        setupLogWindow();
        
        Class controlClass = [UIControl class];
        Method m = class_getInstanceMethod(controlClass, @selector(sendAction:to:forEvent:));
        if (m) {
            orig_controlSendAction = (void (*)(id, SEL, SEL, id, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)swizzled_controlSendAction);
            addLog(@"✅ UIControl sendAction 已 hook (仅记录)");
        }
        
        scanAndHook();
        startPolling();
        
        addLog(@"🚀 初始化完成");
    });
}
