//
//  iphook.m - KFun Bypass 诊断版 v2
//  修复闪退 + 悬浮窗可拖动可复制
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
            if (newText.length > 8000) {
                newText = [newText substringFromIndex:newText.length - 8000];
            }
            g_logView.text = newText;
            [g_logView scrollRangeToVisible:NSMakeRange(newText.length - 1, 1)];
        }
    });
}

// ============================================================
// 🪟 悬浮窗（可拖动 + 可复制）
// ============================================================
@interface LogDragHandler : NSObject
@end
@implementation LogDragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view.superview; // 拖动的是标题栏，移动整个容器
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview];
}
- (void)copyLog:(id)sender {
    if (g_logView) {
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        pb.string = g_logView.text;
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
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    if (ws.windows.count > 0) { keyWindow = ws.windows.firstObject; break; }
                }
            }
        }
        if (!keyWindow) {
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
        
        CGFloat w = 340, h = 280;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(10, 120, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor greenColor].CGColor;
        g_logContainer.layer.borderWidth = 1.5;
        
        // 标题栏（拖动区域）
        UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 30)];
        titleBar.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
        [g_logContainer addSubview:titleBar];
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, w-70, 22)];
        title.text = @"🔍 KFun 诊断 (拖动标题栏)";
        title.textColor = [UIColor greenColor];
        title.font = [UIFont boldSystemFontOfSize:11];
        [titleBar addSubview:title];
        
        // 复制按钮
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w-60, 4, 55, 22);
        [copyBtn setTitle:@"📋复制" forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont systemFontOfSize:10];
        [copyBtn setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
        [copyBtn addTarget:g_dragHandler action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [titleBar addSubview:copyBtn];
        
        // 日志文本（可复制，长按选中文本）
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 32, w-4, h-34)];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:9];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = YES; // 允许选中复制
        g_logView.text = @"[系统] 诊断窗口已启动\n💡 长按日志可全选复制\n💡 拖动标题栏可移动窗口\n";
        [g_logContainer addSubview:g_logView];
        
        // 拖动手势
        g_dragHandler = [[LogDragHandler alloc] init];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_dragHandler action:@selector(handlePan:)];
        [titleBar addGestureRecognizer:pan];
        
        [keyWindow addSubview:g_logContainer];
        addLog(@"✅ 悬浮窗已创建");
    });
}

// ============================================================
// 🔍 安全获取最上层 VC
// ============================================================
static UIViewController *getTopVC() {
    @try {
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
    } @catch (NSException *e) {
        return nil;
    }
}

// ============================================================
// 🔍 安全检测当前 VC（不递归扫描子视图！）
// ============================================================
static void detectCurrentVC() {
    @try {
        UIViewController *vc = getTopVC();
        if (!vc) { addLog(@"⚠️ 未找到当前 VC"); return; }
        
        NSString *clsName = NSStringFromClass([vc class]);
        addLog(@"📱 当前界面: %@", clsName);
        
        // 只检测属性，绝不递归扫描子视图
        NSArray *keys = @[@"authMaskView", @"codeField", @"verifyButton", @"errorLabel", @"successView", @"spinner"];
        for (NSString *key in keys) {
            id val = nil;
            @try { val = [vc valueForKey:key]; } @catch (NSException *e) {}
            if (val) addLog(@"  📌 %@: %@", key, NSStringFromClass([val class]));
        }
    } @catch (NSException *e) {
        addLog(@"❌ detectCurrentVC 异常: %@", e.reason);
    }
}

// ============================================================
// 🖱️ 按钮点击记录
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
    
    // 1. 停止转圈
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
    
    // 2. 隐藏遮罩
    @try {
        id mask = [target valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            addLog(@"✅ authMaskView 已移除");
        }
    } @catch (NSException *e) {}
    
    // 3. 显示成功弹窗
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
    
    // 4. 启动雷达核心
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
    
    // 5. 延迟关闭弹窗
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
// 🎣 Hook 验证类
// ============================================================
static void hookClass(Class cls) {
    if (!cls) return;
    addLog(@"🎣 Hook 类: %s", class_getName(cls));
    
    Method m;
    
    // viewDidLoad（如果存在）
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
    } else {
        addLog(@"  ⚠️ 无 viewDidLoad");
    }
    
    // onTapVerify（如果存在）
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            addLog(@"🎯 onTapVerify 被点击");
            doBypass(self);
        }));
        addLog(@"  ✅ onTapVerify");
    } else {
        addLog(@"  ⚠️ 无 onTapVerify");
    }
    
    // activateCode:completion:
    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *code, id completion) {
            addLog(@"🎯 activateCode: 被调用, code=%@", code);
            doBypass(self);
        }));
        addLog(@"  ✅ activateCode:completion:");
    }
    
    // showError:
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *msg) {
            addLog(@"🛡️ showError 拦截: %@", msg);
            doBypass(self);
        }));
        addLog(@"  ✅ showError:");
    } else {
        addLog(@"  ⚠️ 无 showError:");
    }
    
    // isActivated
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
    } else {
        addLog(@"❌ 未找到验证类");
    }
}

// ============================================================
// 🔄 安全轮询
// ============================================================
static void startPolling() {
    [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *timer) {
        @try {
            detectCurrentVC();
        } @catch (NSException *e) {
            addLog(@"❌ 轮询异常: %@", e.reason);
        }
    }];
    addLog(@"🔄 轮询已启动 (每5秒)");
}

// ============================================================
// 初始化
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[IPH] KFun 诊断版 v2 已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        setupLogWindow();
        
        // Hook UIControl sendAction
        Class controlClass = [UIControl class];
        Method m = class_getInstanceMethod(controlClass, @selector(sendAction:to:forEvent:));
        if (m) {
            orig_controlSendAction = (void (*)(id, SEL, SEL, id, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)swizzled_controlSendAction);
            addLog(@"✅ UIControl sendAction 已 hook");
        }
        
        scanAndHook();
        startPolling();
        
        addLog(@"🚀 初始化完成");
        addLog(@"💡 点击验证按钮看日志");
    });
}
