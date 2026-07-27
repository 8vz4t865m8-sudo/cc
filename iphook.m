//
//  iphook.m - KFun Bypass v15 (零block风险版)
//  策略：showSuccess 传 nil completion，所有初始化用 dispatch_after 延迟执行
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
    NSLog(@"[KFunV15] %@", line);
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
        title.text = @"🔍 KFun v15 (拖动)";
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
// ⭐ 暴力初始化 MainVC（每步独立 try-catch）
// ============================================================
static void forceInitMainVC(UIViewController *mainVC) {
    if (!mainVC) { LOG(@"❌ mainVC nil"); return; }
    LOG(@"🔧 forceInitMainVC begin");

    // 1. 设置 state = 1
    @try {
        [mainVC setValue:@1 forKey:@"state"];
        LOG(@"✅ state = 1");
    } @catch (NSException *e) { LOG(@"❌ state=1: %@", e.reason); }

    // 2. setupAfterActivation
    @try {
        if ([mainVC respondsToSelector:@selector(setupAfterActivation)]) {
            [mainVC performSelector:@selector(setupAfterActivation)];
            LOG(@"✅ setupAfterActivation");
        }
    } @catch (NSException *e) { LOG(@"❌ setupAfterActivation: %@", e.reason); }

    // 3. setupBackgroundKeepAlive
    @try {
        if ([mainVC respondsToSelector:@selector(setupBackgroundKeepAlive)]) {
            [mainVC performSelector:@selector(setupBackgroundKeepAlive)];
            LOG(@"✅ setupBackgroundKeepAlive");
        }
    } @catch (NSException *e) { LOG(@"❌ setupBackgroundKeepAlive: %@", e.reason); }

    // 4. audioPlay
    @try {
        if ([mainVC respondsToSelector:@selector(audioPlay)]) {
            [mainVC performSelector:@selector(audioPlay)];
            LOG(@"✅ audioPlay");
        }
    } @catch (NSException *e) { LOG(@"❌ audioPlay: %@", e.reason); }

    // 5. tableView reloadData
    @try {
        id tv = [mainVC valueForKey:@"tableView"];
        if (tv && [tv respondsToSelector:@selector(reloadData)]) {
            [tv performSelector:@selector(reloadData)];
            LOG(@"✅ tableView reloadData");
        }
    } @catch (NSException *e) { LOG(@"❌ tableView: %@", e.reason); }

    // 6. 设置状态文本
    @try {
        if ([mainVC respondsToSelector:@selector(setStatusText:)]) {
            [mainVC performSelector:@selector(setStatusText:) withObject:@"等待操作"];
        }
        if ([mainVC respondsToSelector:@selector(setDataText:)]) {
            [mainVC performSelector:@selector(setDataText:) withObject:@"等待连接…"];
        }
        LOG(@"✅ 状态文本");
    } @catch (NSException *e) { LOG(@"❌ 状态文本: %@", e.reason); }

    LOG(@"🔧 forceInitMainVC end");
}

// ============================================================
// 🚀 Bypass 核心（零 block 风险）
// ============================================================
static void doBypass(id vcInstance) {
    LOG(@"🚀 Bypass v15 开始");

    // 1. 停止 spinner，隐藏错误，移除遮罩
    @try {
        id spinner = [vcInstance valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
        }
    } @catch (NSException *e) {}

    @try {
        id errorLabel = [vcInstance valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
    } @catch (NSException *e) {}

    @try {
        id mask = [vcInstance valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            LOG(@"✅ authMaskView 移除");
        }
    } @catch (NSException *e) {}

    // 2. 显示假的成功提示（传 nil completion，绝不碰原始 block）
    @try {
        if ([vcInstance respondsToSelector:@selector(showSuccess:completion:)]) {
            [vcInstance performSelector:@selector(showSuccess:completion:) withObject:@"到期时间:2099-12-31 23:59:59" withObject:nil];
            LOG(@"✅ showSuccess 已调用 (nil completion)");
        }
    } @catch (NSException *e) { LOG(@"❌ showSuccess: %@", e.reason); }

    // 3. 同时调用 buildSuccessViewWithExpire
    @try {
        if ([vcInstance respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            [vcInstance performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"到期时间:2099-12-31 23:59:59"];
            LOG(@"✅ buildSuccessViewWithExpire");
        }
    } @catch (NSException *e) { LOG(@"❌ buildSuccessView: %@", e.reason); }

    // 4. 找到 MainVC
    __block UIViewController *mainVC = nil;
    @try {
        if ([vcInstance isKindOfClass:[UIViewController class]]) {
            mainVC = ((UIViewController *)vcInstance).presentingViewController;
        }
    } @catch (NSException *e) {}
    if (!mainVC) {
        Class mainVCClass = objc_getClass(@"ViewController");
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if ([window.rootViewController isKindOfClass:mainVCClass]) {
                mainVC = window.rootViewController;
                break;
            }
        }
    }
    LOG(@"🔧 MainVC = %@", mainVC ? NSStringFromClass([mainVC class]) : @"nil");

    // 5. 延迟 0.5s 后初始化 MainVC（等 showSuccess UI 完成）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        forceInitMainVC(mainVC);

        // 6. 延迟 dismiss
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                if ([vcInstance isKindOfClass:[UIViewController class]]) {
                    UIViewController *vc = (UIViewController *)vcInstance;
                    if (vc.presentingViewController) {
                        [vc dismissViewControllerAnimated:NO completion:^{
                            LOG(@"✅ dismiss 完成");
                            // dismiss 后再初始化一次兜底
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                forceInitMainVC(mainVC);
                            });
                        }];
                    }
                }
            } @catch (NSException *e) { LOG(@"❌ dismiss: %@", e.reason); }
        });
    });
}

// ============================================================
// Hook 入口
// ============================================================
static void hookActivationVC(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
    LOG(@"🎣 Hook: %s", class_getName(cls));

    Method m;

    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [ActVC] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
    }

    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 onTapVerify 拦截");
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(onTapVerify), newIMP, typeEnc);
    }

    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
            LOG(@"🛡️ showError 拦截: %@", msg);
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(showError:), newIMP, typeEnc);
    }

    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            return YES;
        });
        class_replaceMethod(cls, @selector(isActivated), newIMP, typeEnc);
    }

    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            return YES;
        });
        class_replaceMethod(cls, @selector(isVerified), newIMP, typeEnc);
    }
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunV15] v15 零block风险版已加载");
    NSLog(@"========================================");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();

        Class vcClass = objc_getClass(@"WWWActivationViewController");
        if (vcClass) hookActivationVC(vcClass);

        LOG(@"🚀 初始化完成");
    });
}
