//
//  iphook_safe.m - KFun Bypass v13 Safe
//  只绕过验证+加载主页面，不自动启动 exploit/read
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
    NSLog(@"[KFunSafe] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 15000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 15000)];
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
        
        CGFloat w = 350, h = 320;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(8, 100, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.93];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor cyanColor].CGColor;
        g_logContainer.layer.borderWidth = 1.2;
        
        UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 28)];
        titleBar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        [g_logContainer addSubview:titleBar];
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(6, 3, w-80, 22)];
        title.text = @"🔍 KFun Safe (拖动)";
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
// 找到真正的 ViewController
// ============================================================
static UIViewController *findMainVC() {
    Class mainClass = objc_getClass("ViewController");
    if (!mainClass) return nil;
    
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *root = window.rootViewController;
        if (!root) continue;
        
        if ([root isKindOfClass:mainClass]) return root;
        
        if ([root isKindOfClass:[UITabBarController class]]) {
            UITabBarController *tab = (UITabBarController *)root;
            for (UIViewController *vc in tab.viewControllers) {
                if ([vc isKindOfClass:mainClass]) return vc;
                if ([vc isKindOfClass:[UINavigationController class]]) {
                    UINavigationController *nav = (UINavigationController *)vc;
                    for (UIViewController *child in nav.viewControllers) {
                        if ([child isKindOfClass:mainClass]) return child;
                    }
                }
            }
        }
        
        if ([root isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)root;
            for (UIViewController *vc in nav.viewControllers) {
                if ([vc isKindOfClass:mainClass]) return vc;
            }
        }
        
        UIViewController *presented = root.presentedViewController;
        if ([presented isKindOfClass:mainClass]) return presented;
    }
    return nil;
}

// ============================================================
// ⭐ 安全初始化：只加载UI，不启动 exploit/read
// ============================================================
static void initActivationVC(id actVC) {
    if (!actVC) return;
    LOG(@"🔧 初始化 ActivationVC（仅UI，不启动内存读取）");
    
    // 1. 调用 setupAfterActivation（激活后初始化）
    @try {
        if ([actVC respondsToSelector:@selector(setupAfterActivation)]) {
            [actVC performSelector:@selector(setupAfterActivation)];
            LOG(@"✅ setupAfterActivation");
        }
    } @catch (NSException *e) { LOG(@"❌ setupAfterActivation: %@", e.reason); }
    
    // 2. 调用 buildUI（构建主页面 UI）
    @try {
        if ([actVC respondsToSelector:@selector(buildUI)]) {
            [actVC performSelector:@selector(buildUI)];
            LOG(@"✅ buildUI");
        }
    } @catch (NSException *e) { LOG(@"❌ buildUI: %@", e.reason); }
    
    // 3. 启动持续验证心跳（让 app 认为一直有效）
    @try {
        if ([actVC respondsToSelector:@selector(startContinuousAuthCheck)]) {
            [actVC performSelector:@selector(startContinuousAuthCheck)];
            LOG(@"✅ startContinuousAuthCheck");
        }
    } @catch (NSException *e) { LOG(@"❌ startContinuousAuthCheck: %@", e.reason); }
    
    // 4. 调用 transitionTo: 切换到主页面
    @try {
        if ([actVC respondsToSelector:@selector(transitionTo:)]) {
            [actVC performSelector:@selector(transitionTo:) withObject:@"main"];
            LOG(@"✅ transitionTo:main");
        }
    } @catch (NSException *e) { LOG(@"❌ transitionTo: %@", e.reason); }
}

// ============================================================
// ⭐ 安全初始化主页面：只设置状态，不自动启动 exploit/read
// ============================================================
static void initMainVC(UIViewController *mainVC) {
    if (!mainVC) { LOG(@"❌ MainVC nil"); return; }
    LOG(@"🔧 初始化 MainVC（仅UI状态，不启动内存读取）");
    
    // 只设置状态文本，不调用 exploit/read
    @try {
        if ([mainVC respondsToSelector:@selector(setStatusText:)]) {
            [mainVC performSelector:@selector(setStatusText:) withObject:@"已连接（等待启动）"];
            LOG(@"✅ setStatusText");
        }
        if ([mainVC respondsToSelector:@selector(setDataText:)]) {
            [mainVC performSelector:@selector(setDataText:) withObject:@"请点击功能按钮启动"];
            LOG(@"✅ setDataText");
        }
    } @catch (NSException *e) { LOG(@"❌ 设置文本: %@", e.reason); }
    
    // 后台保活可以开，这个安全
    @try {
        if ([mainVC respondsToSelector:@selector(setupBackgroundKeepAlive)]) {
            [mainVC performSelector:@selector(setupBackgroundKeepAlive)];
            LOG(@"✅ setupBackgroundKeepAlive");
        }
    } @catch (NSException *e) { LOG(@"❌ setupBackgroundKeepAlive: %@", e.reason); }
    
    LOG(@"⚠️ exploit/read 未自动启动，需用户手动点击");
}

// ============================================================
// Bypass 执行
// ============================================================
static void doBypass(id actVC) {
    LOG(@"🚀 Bypass 开始（安全模式）");
    if (!actVC) { LOG(@"❌ actVC nil"); return; }
    
    // 1. 停止 spinner
    @try {
        id spinner = [actVC valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
            LOG(@"✅ spinner 停止");
        }
    } @catch (NSException *e) {}
    
    // 2. 隐藏错误标签
    @try {
        id errorLabel = [actVC valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
    } @catch (NSException *e) {}
    
    // 3. 移除认证遮罩
    @try {
        id mask = [actVC valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            LOG(@"✅ authMaskView 移除");
        }
    } @catch (NSException *e) {}
    
    // 4. 初始化激活页（setupAfterActivation + buildUI + transitionTo）
    initActivationVC(actVC);
    
    // 5. 调用 showSuccess:completion:
    @try {
        if ([actVC respondsToSelector:@selector(showSuccess:completion:)]) {
            id completionBlock = ^(void) {
                LOG(@"🎉 showSuccess completion 执行");
            };
            [actVC performSelector:@selector(showSuccess:completion:) 
                        withObject:@"到期时间:2099-12-31 23:59:59" 
                        withObject:completionBlock];
            LOG(@"✅ showSuccess:completion: 已调用");
        }
    } @catch (NSException *e) { LOG(@"❌ showSuccess:completion: %@", e.reason); }
    
    // 6. 延迟后初始化主页面（只设置状态，不启动 exploit）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *mainVC = findMainVC();
        if (mainVC) {
            initMainVC(mainVC);
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *retryVC = findMainVC();
                if (retryVC) initMainVC(retryVC);
            });
        }
    });
    
    // 7. dismiss 激活页面
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([actVC isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)actVC;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:nil];
                    LOG(@"✅ dismiss 完成");
                } else if (vc.navigationController) {
                    [vc.navigationController popViewControllerAnimated:NO];
                    LOG(@"✅ popViewController 完成");
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// Hook 入口
// ============================================================
static void hookActivationVC(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
    LOG(@"🎣 Hook: %s", class_getName(cls));
    Method m;
    
    // 1. Hook viewDidLoad
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [ActVC] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try {
                    id isAct = [self valueForKey:@"isActivated"];
                    if (![isAct boolValue]) {
                        LOG(@"⚡ 自动触发 bypass（未激活状态）");
                        doBypass(self);
                    }
                } @catch (NSException *e) {}
            });
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
        LOG(@"  ✅ viewDidLoad");
    }
    
    // 2. ⭐ Hook verifyWithCompletion:（核心）
    m = class_getInstanceMethod(cls, NSSelectorFromString(@"verifyWithCompletion:"));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, id completion) {
            LOG(@"🎯 verifyWithCompletion: 拦截");
            if (completion) {
                @try {
                    NSDictionary *fakeData = @{
                        @"success": @YES,
                        @"message": @"ok",
                        @"data": @{
                            @"expires_at": @"2099-12-31T23:59:59Z",
                            @"vip_time": @"2099-12-31"
                        }
                    };
                    void (^compBlock)(id) = (void (^)(id))completion;
                    compBlock(fakeData);
                    LOG(@"✅ completion 已调用");
                } @catch (NSException *e) {
                    @try {
                        void (^compBlock)(void) = (void (^)(void))completion;
                        compBlock();
                    } @catch (NSException *e2) {}
                }
            }
            doBypass(self);
        });
        class_replaceMethod(cls, NSSelectorFromString(@"verifyWithCompletion:"), newIMP, typeEnc);
        LOG(@"  ✅ verifyWithCompletion:");
    }
    
    // 3. Hook onTapVerify
    m = class_getInstanceMethod(cls, NSSelectorFromString(@"onTapVerify"));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 onTapVerify 拦截");
            doBypass(self);
        });
        class_replaceMethod(cls, NSSelectorFromString(@"onTapVerify"), newIMP, typeEnc);
        LOG(@"  ✅ onTapVerify");
    }
    
    // 4. Hook showError:
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
            LOG(@"🛡️ showError 拦截: %@", msg);
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(showError:), newIMP, typeEnc);
        LOG(@"  ✅ showError:");
    }
    
    // 5. Hook isActivated → YES
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
        class_replaceMethod(cls, @selector(isActivated), newIMP, typeEnc);
        LOG(@"  ✅ isActivated -> YES");
    }
    
    // 6. Hook isVerified → YES
    m = class_getInstanceMethod(cls, NSSelectorFromString(@"isVerified"));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
        class_replaceMethod(cls, NSSelectorFromString(@"isVerified"), newIMP, typeEnc);
        LOG(@"  ✅ isVerified -> YES");
    }
    
    // 7. Hook setStatus: 拦截错误
    m = class_getInstanceMethod(cls, NSSelectorFromString(@"setStatus:"));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, id status) {
            LOG(@"🛡️ setStatus: 拦截 -> %@", status);
            if ([status isKindOfClass:[NSString class]] && 
                ([status containsString:@"error"] || [status containsString:@"失败"])) {
                doBypass(self);
            }
        });
        class_replaceMethod(cls, NSSelectorFromString(@"setStatus:"), newIMP, typeEnc);
        LOG(@"  ✅ setStatus:");
    }
}

static void hookViewController(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 ViewController"); return; }
    LOG(@"🎣 Hook MainVC: %s", class_getName(cls));
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [MainVC] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
            // 只设置状态，不启动 exploit
            initMainVC(self);
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
        LOG(@"  ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [MainVC] viewDidAppear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
            initMainVC(self);
        });
        class_replaceMethod(cls, @selector(viewDidAppear:), newIMP, typeEnc);
        LOG(@"  ✅ viewDidAppear:");
    }
    
    // ⭐ 保护 exploit/read 方法，但不在 bypass 时自动调用
    // 这些留给用户手动点击触发
    NSArray *methods = @[@"exploitTapped", @"readTapped", @"readLoop"];
    for (NSString *selName in methods) {
        SEL sel = NSSelectorFromString(selName);
        m = class_getInstanceMethod(cls, sel);
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *typeEnc = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG(@"🎯 [MainVC] %@ 用户手动触发", selName);
                ((void (*)(id, SEL))orig)(self, sel);
            });
            class_replaceMethod(cls, sel, newIMP, typeEnc);
            LOG(@"  ✅ %@ (保护，不自动调用)", selName);
        }
    }
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunSafe] v13 安全版已加载（不自动启动 exploit）");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        
        Class actClass = objc_getClass("WWWActivationViewController");
        if (actClass) hookActivationVC(actClass);
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        
        LOG(@"🚀 初始化完成");
        LOG(@"📋 安全说明：");
        LOG(@"   • 自动绕过验证 ✅");
        LOG(@"   • 自动加载主页面 ✅");
        LOG(@"   • 自动启动 exploit ❌（需手动点击）");
        LOG(@"   • 自动启动 read ❌（需手动点击）");
    });
}
