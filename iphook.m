//
//  iphook.m - KFun Bypass v18
//  策略：模拟正版时间线 + viewDidAppear/setState 内自动加载 + libxpf 调用
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;
static BOOL g_bypassTriggered = NO;

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunV18] %@", line);
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

@interface DragHandler : NSObject
@end
@implementation DragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view.superview;
    CGPoint t = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}
- (void)copyLog:(id)sender {
    if (g_logBuffer.length) {
        UIPasteboard.generalPasteboard.string = g_logBuffer;
        LOG(@"📋 已复制 (%lu 字符)", (unsigned long)g_logBuffer.length);
    }
}
@end
static DragHandler *g_drag = nil;

static void setupWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DragHandler *dh = [[DragHandler alloc] init];
        g_drag = dh;
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)s).activationState == UISceneActivationStateForegroundActive) {
                    if (((UIWindowScene *)s).windows.count) { kw = ((UIWindowScene *)s).windows.firstObject; break; }
                }
            }
        }
        if (!kw) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            kw = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
            #pragma clang diagnostic pop
        }
        if (!kw) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupWindow(); }); return; }
        
        CGFloat w = 350, h = 280;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(8, 100, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.93];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor cyanColor].CGColor;
        g_logContainer.layer.borderWidth = 1.2;
        
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 26)];
        bar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        [g_logContainer addSubview:bar];
        
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(6, 3, w-80, 20)];
        t.text = @"🔍 KFun v18 时间线修复 (拖动)";
        t.textColor = [UIColor cyanColor];
        t.font = [UIFont boldSystemFontOfSize:10];
        [bar addSubview:t];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w-70, 2, 65, 22);
        [copyBtn setTitle:@"📋复制" forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont systemFontOfSize:9];
        [copyBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        [copyBtn addTarget:dh action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:copyBtn];
        
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 28, w-4, h-30)];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:8];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = YES;
        [g_logContainer addSubview:g_logView];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:dh action:@selector(handlePan:)];
        [bar addGestureRecognizer:pan];
        
        [kw addSubview:g_logContainer];
        LOG(@"✅ v18 悬浮窗启动");
    });
}

static void snap(id obj, NSString *label) {
    if (!obj) return;
    LOG(@"📸 [%@] %@", label, NSStringFromClass([obj class]));
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        if (![name isEqualToString:@"state"] && 
            ![name isEqualToString:@"tableView"] && 
            ![name isEqualToString:@"statusText"] && 
            ![name isEqualToString:@"dataText"] && 
            ![name isEqualToString:@"authMaskView"] &&
            ![name isEqualToString:@"busy"] &&
            ![name hasSuffix:@"Data"] &&
            ![name hasSuffix:@"Result"] &&
            ![name hasSuffix:@"Config"] &&
            ![name hasSuffix:@"Token"] &&
            ![name hasSuffix:@"Key"] &&
            ![name hasSuffix:@"Expire"]) continue;
        @try {
            id val = [obj valueForKey:name];
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 120) desc = [desc substringToIndex:120];
            LOG(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {}
    }
    if (props) free(props);
}

// 递归查找
static UIViewController *findVC(Class target, UIViewController *vc) {
    if (!vc) return nil;
    if ([vc isKindOfClass:target]) return vc;
    UIViewController *found = findVC(target, [vc presentedViewController]);
    if (found) return found;
    for (UIViewController *c in [vc childViewControllers]) {
        found = findVC(target, c);
        if (found) return found;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        for (UIViewController *c in [(UITabBarController *)vc viewControllers]) {
            found = findVC(target, c);
            if (found) return found;
        }
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *c in [(UINavigationController *)vc viewControllers]) {
            found = findVC(target, c);
            if (found) return found;
        }
    }
    return nil;
}

// ============================================================
// ⭐ v18 核心：触发 MainVC 加载的所有可能方式
// ============================================================
static void triggerLoading(UIViewController *mainVC, NSString *source) {
    LOG(@"💥 [%@] 触发加载...", source);
    snap(mainVC, [NSString stringWithFormat:@"MainVC(%@前)", source]);
    
    // 1. 尝试调用所有可能的方法
    NSArray *methods = @[
        @"loadData", @"refreshData", @"reloadData", @"fetchData", @"updateData",
        @"loadConfig", @"refreshConfig", @"fetchConfig", @"updateConfig",
        @"startRadar", @"startLoading", @"initialize", @"setupUI",
        @"loadContent", @"refreshContent", @"updateUI", @"renderUI",
        @"setupTableView", @"createTableView", @"initTableView",
        @"reloadView", @"refreshView", @"updateView",
        @"onAuthSuccess", @"handleAuthSuccess", @"didVerify", @"didActivate"
    ];
    for (NSString *name in methods) {
        SEL sel = NSSelectorFromString(name);
        if ([mainVC respondsToSelector:sel]) {
            @try {
                NSMethodSignature *sig = [mainVC methodSignatureForSelector:sel];
                if (!sig) continue;
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:mainVC];
                [inv setSelector:sel];
                NSUInteger nargs = [sig numberOfArguments];
                if (nargs == 3) {
                    if (strcmp([sig getArgumentTypeAtIndex:2], "B") == 0) {
                        BOOL val = NO; [inv setArgument:&val atIndex:2];
                    } else if (strcmp([sig getArgumentTypeAtIndex:2], "@") == 0) {
                        id val = nil; [inv setArgument:&val atIndex:2];
                    }
                }
                [inv invoke];
                LOG(@"✅ 调用 %@ 成功", name);
            } @catch (NSException *e) {}
        }
    }
    
    // 2. 强制创建 tableView（如果 nil）
    @try {
        id tv = [mainVC valueForKey:@"tableView"];
        if (!tv) {
            UITableView *tableView = [[UITableView alloc] initWithFrame:mainVC.view.bounds style:UITableViewStylePlain];
            [mainVC.view addSubview:tableView];
            // 尝试设置属性
            @try { [mainVC setValue:tableView forKey:@"tableView"]; LOG(@"✅ 创建并设置 tableView"); } @catch (NSException *e) {}
        } else if ([tv isKindOfClass:[UITableView class]]) {
            [(UITableView *)tv reloadData];
            LOG(@"✅ tableView reloadData");
        }
    } @catch (NSException *e) {}
    
    // 3. 刷新 view
    @try {
        [mainVC.view setNeedsLayout];
        [mainVC.view layoutIfNeeded];
        [mainVC.view setNeedsDisplay];
        LOG(@"✅ view 刷新");
    } @catch (NSException *e) {}
    
    // 4. 发送通知
    NSArray *notifs = @[
        @"KFunAuthSuccess", @"KFunDidActivate", @"AuthSuccess", @"DidActivate",
        @"LoginSuccess", @"VerificationSuccess"
    ];
    for (NSString *name in notifs) {
        @try {
            [[NSNotificationCenter defaultCenter] postNotificationName:name object:mainVC userInfo:@{@"success": @YES}];
        } @catch (NSException *e) {}
    }
    LOG(@"✅ 通知已发送");
    
    snap(mainVC, [NSString stringWithFormat:@"MainVC(%@后)", source]);
}

// ============================================================
// 🚀 Bypass 核心 - v18
// ============================================================
static void doBypass(id vcInstance) {
    LOG(@"🚀 Bypass v18 开始");
    g_bypassTriggered = YES;
    
    // 1. 停止 spinner
    @try {
        id spinner = [vcInstance valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
        }
    } @catch (NSException *e) {}
    
    // 2. 隐藏错误提示
    @try {
        id errorLabel = [vcInstance valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
    } @catch (NSException *e) {}
    
    // 3. 移除遮罩
    @try {
        id mask = [vcInstance valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
        }
    } @catch (NSException *e) {}
    
    // 4. 调用 showSuccess:completion:（传入 nil，模拟正版弹窗）
    @try {
        if ([vcInstance respondsToSelector:@selector(showSuccess:completion:)]) {
            LOG(@"⭐ 调用 showSuccess:completion:...");
            [vcInstance performSelector:@selector(showSuccess:completion:) withObject:@"到期时间:2099-12-31 23:59:59" withObject:nil];
            LOG(@"✅ showSuccess 已调用");
        }
    } @catch (NSException *e) {}
    
    // 5. 调用 buildSuccessViewWithExpire:
    @try {
        if ([vcInstance respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            [vcInstance performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"到期时间:2099-12-31 23:59:59"];
        }
    } @catch (NSException *e) {}
    
    // 6. ⭐ 模拟正版 2.5 秒时间线，然后 dismiss
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LOG(@"⭐ 2.5秒到，开始 dismiss...");
        
        @try {
            if ([vcInstance isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)vcInstance;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:^{
                        LOG(@"✅ dismiss 完成");
                    }];
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// Hook 入口
// ============================================================
static void hookActivationVC(Class cls) {
    if (!cls) return;
    LOG(@"🎣 Hook ActVC");
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 onTapVerify 拦截");
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(onTapVerify), newIMP, te);
    }
    
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
            LOG(@"🛡️ showError: %@", msg);
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(showError:), newIMP, te);
    }
    
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        const char *te = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
        class_replaceMethod(cls, @selector(isActivated), newIMP, te);
    }
    
    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) {
        const char *te = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
        class_replaceMethod(cls, @selector(isVerified), newIMP, te);
    }
}

static void hookViewController(Class cls) {
    if (!cls) return;
    LOG(@"🎣 Hook MainVC");
    
    Method m;
    
    // ⭐ 关键：viewDidAppear: 被触发时自动加载
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [MainVC] viewDidAppear: (bypass=%d)", g_bypassTriggered);
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
            
            // 如果 bypass 已触发，自动触发加载
            if (g_bypassTriggered) {
                triggerLoading(self, @"viewDidAppear");
            }
            snap(self, @"MainVC(viewDidAppear)");
        });
        class_replaceMethod(cls, @selector(viewDidAppear:), newIMP, te);
    }
    
    // ⭐ 关键：setState: 被调用时自动加载
    m = class_getInstanceMethod(cls, @selector(setState:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSInteger state) {
            LOG(@"🔔 [MainVC] setState: %ld (bypass=%d)", (long)state, g_bypassTriggered);
            ((void (*)(id, SEL, NSInteger))orig)(self, @selector(setState:), state);
            
            // 如果 bypass 已触发，自动触发加载
            if (g_bypassTriggered) {
                triggerLoading(self, [NSString stringWithFormat:@"setState:%ld", (long)state]);
            }
            snap(self, [NSString stringWithFormat:@"MainVC(setState:%ld)", (long)state]);
        });
        class_replaceMethod(cls, @selector(setState:), newIMP, te);
    }
    
    // viewDidLoad 也触发一次
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [MainVC] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
            if (g_bypassTriggered) {
                triggerLoading(self, @"viewDidLoad");
            }
            snap(self, @"MainVC(viewDidLoad)");
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, te);
    }
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"[KFunV18] v18 已加载");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWindow();
        
        Class vcClass = objc_getClass("WWWActivationViewController");
        if (vcClass) hookActivationVC(vcClass);
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        
        LOG(@"🚀 v18 初始化完成");
        LOG(@"📋 点击验证 → 等3秒 → 看主页面");
    });
}
