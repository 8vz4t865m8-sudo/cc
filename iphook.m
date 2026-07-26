//
//  iphook.m - KFun Bypass 精准版 v3 (ARC修复)
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
            if (newText.length > 8000) newText = [newText substringFromIndex:newText.length - 8000];
            g_logView.text = newText;
            [g_logView scrollRangeToVisible:NSMakeRange(newText.length - 1, 1)];
        }
    });
}

@interface LogDragHandler : NSObject
@end
@implementation LogDragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view.superview;
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:(CGPoint){0,0} inView:view.superview];
}
- (void)copyLog:(id)sender {
    if (g_logView) {
        UIPasteboard.generalPasteboard.string = g_logView.text;
        addLog(@"📋 日志已复制");
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
        if (!keyWindow) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupLogWindow(); }); return; }
        
        CGFloat w = 340, h = 280;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(10, 120, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor greenColor].CGColor;
        g_logContainer.layer.borderWidth = 1.5;
        
        UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 30)];
        titleBar.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
        [g_logContainer addSubview:titleBar];
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, w-70, 22)];
        title.text = @"🔍 KFun 诊断 (拖动标题栏)";
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
        g_logView.text = @"[系统] 诊断窗口已启动\n";
        [g_logContainer addSubview:g_logView];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_dragHandler action:@selector(handlePan:)];
        [titleBar addGestureRecognizer:pan];
        
        [keyWindow addSubview:g_logContainer];
        addLog(@"✅ 悬浮窗已创建");
    });
}

static void doBypass(id vcInstance) {
    addLog(@"🚀 开始 Bypass...");
    
    @try {
        id spinner = [vcInstance valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
            addLog(@"✅ spinner 已停止");
        }
    } @catch (NSException *e) {}
    
    @try {
        if ([vcInstance respondsToSelector:@selector(setLoading:)]) {
            [vcInstance performSelector:@selector(setLoading:) withObject:@NO];
        }
    } @catch (NSException *e) {}
    
    @try {
        id mask = [vcInstance valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            addLog(@"✅ authMaskView 已移除");
        }
    } @catch (NSException *e) {}
    
    @try {
        id errorLabel = [vcInstance valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
    } @catch (NSException *e) {}
    
    @try {
        if ([vcInstance respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            [vcInstance performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
            addLog(@"✅ buildSuccessViewWithExpire: 已调用");
        } else {
            addLog(@"⚠️ 无 buildSuccessViewWithExpire:");
        }
    } @catch (NSException *e) {
        addLog(@"❌ buildSuccessViewWithExpire: 失败: %@", e.reason);
    }
    
    @try {
        if ([vcInstance respondsToSelector:@selector(setupAfterActivation)]) {
            [vcInstance performSelector:@selector(setupAfterActivation)];
            addLog(@"✅ setupAfterActivation 已调用");
        } else {
            addLog(@"⚠️ 无 setupAfterActivation");
        }
    } @catch (NSException *e) {
        addLog(@"❌ setupAfterActivation 失败: %@", e.reason);
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([vcInstance isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)vcInstance;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:nil];
                    addLog(@"✅ dismiss 验证弹窗");
                }
            }
        } @catch (NSException *e) {}
    });
}

static void hookVCClass(Class cls) {
    if (!cls) { addLog(@"❌ 未找到 WWWActivationViewController"); return; }
    addLog(@"🎣 Hook VC: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            addLog(@"🎯 viewDidLoad 触发");
            struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&super, @selector(viewDidLoad));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                doBypass(self);
            });
        }));
        addLog(@"  ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            addLog(@"🎯 onTapVerify 被拦截");
            doBypass(self);
        }));
        addLog(@"  ✅ onTapVerify");
    } else {
        addLog(@"  ⚠️ 无 onTapVerify");
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
    
    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            return YES;
        }));
        addLog(@"  ✅ isVerified -> YES");
    }
}

// ============================================================
// Hook UIControl sendAction（C函数方式，兼容ARC）
// ============================================================
static void (*orig_controlSendAction)(id, SEL, SEL, id, id);

static void swizzled_controlSendAction(id self, SEL _cmd, SEL action, id target, UIEvent *event) {
    if ([self isKindOfClass:[UIButton class]]) {
        addLog(@"🖱️ 按钮点击: %@ -> %@.%@", NSStringFromClass([self class]), target ? NSStringFromClass([target class]) : @"nil", NSStringFromSelector(action));
    }
    orig_controlSendAction(self, _cmd, action, target, event);
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[IPH] KFun 精准版 v3 已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        setupLogWindow();
        
        Class controlClass = [UIControl class];
        Method m = class_getInstanceMethod(controlClass, @selector(sendAction:to:forEvent:));
        if (m) {
            orig_controlSendAction = (void (*)(id, SEL, SEL, id, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)swizzled_controlSendAction);
            addLog(@"✅ UIControl sendAction 已 hook");
        }
        
        Class vcClass = objc_getClass("WWWActivationViewController");
        if (vcClass) hookVCClass(vcClass);
        
        addLog(@"🚀 初始化完成");
    });
}
