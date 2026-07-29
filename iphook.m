//
//  iphook.m - v18 最终暴力模拟版
//  原理：拦截原App验证，然后模仿KfunHook的成功路径
//  方法：直接调用KfunHook的setupAfterActivation（如果存在），否则暴力刷新所有视图
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

// ---------- 悬浮窗 ----------
static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;
static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunV18] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 20000) [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 20000)];
    dispatch_async(dispatch_get_main_queue(), ^{ if (g_logView) { g_logView.text = g_logBuffer; [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)]; } });
}
@interface LogDragHandler : NSObject @end
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
        title.text = @"🔍 KFun v18 暴力模拟 (拖动)";
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
        LOG(@"✅ v18 暴力模拟已启动");
    });
}

// ---------- 工具：打印对象属性 ----------
static void snapshotProperties(id obj, NSString *label) {
    if (!obj) { LOG(@"❌ %@ nil", label); return; }
    LOG(@"📸 [%@] begin", label);
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            id val = [obj valueForKey:name];
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 100) desc = [desc substringToIndex:100];
            LOG(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {
            LOG(@"   %@ = [err:%@]", name, e.reason);
        }
    }
    if (props) free(props);
    LOG(@"📸 [%@] end", label);
}

// ---------- 暴力刷新主界面 ----------
static void forceRefreshMainViewController() {
    // 1. 写入所有可能的激活状态（覆盖各种key）
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *dict = @{
        @"status": @"ok",
        @"activationStatus": @"ok",
        @"activated": @"1",
        @"isActivated": @YES,
        @"expires_at": @"2099-12-31 23:59:59",
        @"expire": @"2099-12-31 23:59:59",
        @"vip_time": @"2099-12-31 23:59:59"
    };
    for (NSString *key in dict) {
        [defaults setObject:dict[key] forKey:key];
    }
    [defaults synchronize];
    LOG(@"✅ 已写入多个激活状态 key");

    // 2. 获取主控制器 ViewController
    Class mainClass = objc_getClass("ViewController");
    if (!mainClass) {
        LOG(@"❌ 未找到 ViewController 类");
        return;
    }
    UIViewController *mainVC = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *root = window.rootViewController;
        if ([root isKindOfClass:[UITabBarController class]]) {
            root = [(UITabBarController *)root selectedViewController];
        }
        if ([root isKindOfClass:[UINavigationController class]]) {
            root = [(UINavigationController *)root topViewController];
        }
        if ([root isKindOfClass:mainClass]) {
            mainVC = root;
            break;
        }
        for (UIViewController *child in root.childViewControllers) {
            if ([child isKindOfClass:mainClass]) {
                mainVC = child;
                break;
            }
        }
        if (mainVC) break;
    }
    if (!mainVC) {
        LOG(@"❌ 未找到主控制器实例");
        return;
    }
    LOG(@"🎯 找到主控制器: %@", mainVC);
    snapshotProperties(mainVC, @"主控制器(激活前)");

    // 3. 尝试调用 KfunHook 的 setupAfterActivation（如果内存中有该实例）
    // 遍历所有视图控制器，查找 WWWActivationViewController 实例，调用它的 setupAfterActivation
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *root = window.rootViewController;
        [self traverseViewController:root];
    }
    // 如果找到并调用了，就不需要下面的暴力设置了，因为 KfunHook 会帮我们搞定
    // 但我们还是继续执行暴力刷新，以防万一

    // 4. 设置各种可能的状态属性
    NSArray *stateKeys = @[@"state", @"status", @"activationStatus", @"isActivated", @"activated", @"isVerified"];
    for (NSString *key in stateKeys) {
        @try {
            [mainVC setValue:@(1) forKey:key];
            LOG(@"  设置 %@ = 1", key);
        } @catch (NSException *e) {}
        @try {
            [mainVC setValue:@"ok" forKey:key];
        } @catch (NSException *e) {}
        @try {
            [mainVC setValue:@YES forKey:key];
        } @catch (NSException *e) {}
    }
    // 直接修改 _state ivar
    Ivar stateIvar = class_getInstanceVariable(mainClass, "_state");
    if (stateIvar) {
        object_setIvar(mainVC, stateIvar, @(1));
        LOG(@"  直接设 _state = 1");
    }

    // 5. 调用所有可能的刷新方法
    NSArray *refreshMethods = @[
        @"reloadData", @"refreshData", @"loadData", @"updateData",
        @"setup", @"setupUI", @"refreshUI", @"updateUI",
        @"loadContent", @"refreshContent", @"fetchData",
        @"viewDidLoad", @"viewWillAppear:", @"viewDidAppear:",
        @"startRadar", @"startLoading", @"initialize",
        @"reloadTableView", @"refreshTableView"
    ];
    for (NSString *methodName in refreshMethods) {
        SEL sel = NSSelectorFromString(methodName);
        if ([mainVC respondsToSelector:sel]) {
            @try {
                // 处理带参数的方法 (viewWillAppear: 等)
                if ([methodName hasSuffix:@":"]) {
                    [mainVC performSelector:sel withObject:@(YES)];
                } else {
                    [mainVC performSelector:sel];
                }
                LOG(@"  调用 [%@] 成功", methodName);
            } @catch (NSException *e) {
                LOG(@"  调用 [%@] 异常: %@", methodName, e.reason);
            }
        }
    }

    // 6. 刷新所有 UITableView 和 UICollectionView
    [self refreshAllTableAndCollectionViewsInView:mainVC.view];

    // 7. 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ActivationSuccessNotification" object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kActivationDidComplete" object:nil];
    LOG(@"📢 已发送激活成功通知");

    // 8. 延迟再次刷新
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshAllTableAndCollectionViewsInView:mainVC.view];
        [mainVC.view setNeedsLayout];
        [mainVC.view layoutIfNeeded];
        LOG(@"✅ 二次刷新完成");
        snapshotProperties(mainVC, @"主控制器(激活后)");
    });
}

// 辅助：遍历视图控制器，尝试调用 KfunHook 的 setupAfterActivation
static void traverseViewController(UIViewController *vc) {
    if (!vc) return;
    if ([vc isKindOfClass:objc_getClass("WWWActivationViewController")]) {
        if ([vc respondsToSelector:@selector(setupAfterActivation)]) {
            LOG(@"🎯 找到 WWWActivationViewController，调用 setupAfterActivation");
            [vc performSelector:@selector(setupAfterActivation)];
            LOG(@"✅ 已调用 setupAfterActivation");
        }
    }
    for (UIViewController *child in vc.childViewControllers) {
        traverseViewController(child);
    }
    if (vc.presentedViewController) {
        traverseViewController(vc.presentedViewController);
    }
}

// 辅助：刷新所有表格和集合视图
static void refreshAllTableAndCollectionViewsInView(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[UITableView class]]) {
        [(UITableView *)view reloadData];
        LOG(@"🔄 刷新 UITableView: %@", view);
    } else if ([view isKindOfClass:[UICollectionView class]]) {
        [(UICollectionView *)view reloadData];
        LOG(@"🔄 刷新 UICollectionView: %@", view);
    }
    for (UIView *subview in view.subviews) {
        refreshAllTableAndCollectionViewsInView(subview);
    }
}

// ---------- 拦截原App验证（如弹窗、按钮） ----------
static void doBypass(id vcInstance) {
    LOG(@"🚀 拦截激活请求，执行暴力模拟");

    // 隐藏激活界面元素（如果存在）
    @try {
        id spinner = [vcInstance valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
        }
        id errorLabel = [vcInstance valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
        id mask = [vcInstance valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
        }
        LOG(@"✅ 已清理激活界面");
    } @catch (NSException *e) {}

    // 执行暴力刷新
    forceRefreshMainViewController();

    // 延迟关闭激活控制器
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([vcInstance isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)vcInstance;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:^{
                        LOG(@"✅ 激活页面已关闭");
                    }];
                }
            }
        } @catch (NSException *e) {}
    });
}

// ---------- Hook 入口 ----------
static void hookActivationVC(Class cls) {
    if (!cls) { LOG(@"❌ 未找到激活控制器类"); return; }
    LOG(@"🎣 Hook: %s", class_getName(cls));
    
    Method m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 onTapVerify 拦截");
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(onTapVerify), newIMP, typeEnc);
        LOG(@"  ✅ onTapVerify");
    }
    
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
            LOG(@"🛡️ showError 拦截 -> 转为绕过");
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(showError:), newIMP, typeEnc);
        LOG(@"  ✅ showError:");
    }
    
    // 强制 isActivated / isVerified 返回 YES
    NSArray *selNames = @[@"isActivated", @"isVerified"];
    for (NSString *selName in selNames) {
        SEL sel = NSSelectorFromString(selName);
        Method m2 = class_getInstanceMethod(cls, sel);
        if (m2) {
            const char *typeEnc = method_getTypeEncoding(m2);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                return YES;
            });
            class_replaceMethod(cls, sel, newIMP, typeEnc);
            LOG(@"  ✅ %@ -> YES", selName);
        }
    }
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunV18] 暴力模拟最终版加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        Class actClass = objc_getClass("WWWActivationViewController");
        if (actClass) hookActivationVC(actClass);
        LOG(@"🚀 v18 初始化完成，点击验证即可尝试加载主界面");
    });
}
