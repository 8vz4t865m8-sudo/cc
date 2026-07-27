//
//  iphook.m - KFun Bypass v20
//  修复：用 NSInvocation 安全传递 block，防闪退
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
    NSLog(@"[KFunV20] %@", line);
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
        t.text = @"🔍 KFun v20 NSInvocation (拖动)";
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
        LOG(@"✅ v20 悬浮窗启动");
    });
}

// ============================================================
// 🌿 自然 bypass：只把 showError: 改成 showSuccess:completion:
// 用 NSInvocation 安全传递 block
// ============================================================
static void naturalBypass(id vcInstance) {
    LOG(@"🌿 自然 bypass 触发");
    
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
    
    // 4. 获取 onVerify block（App 自己的 completion）
    id completion = nil;
    @try {
        completion = [vcInstance valueForKey:@"onVerify"];
        LOG(@"🌿 onVerify = %@ (类型: %@)", completion, completion ? NSStringFromClass([completion class]) : @"nil");
    } @catch (NSException *e) {
        LOG(@"⚠️ 获取 onVerify 失败: %@", e.reason);
    }
    
    // 5. ⭐ 用 NSInvocation 安全调用 showSuccess:completion:
    @try {
        SEL sel = @selector(showSuccess:completion:);
        if ([vcInstance respondsToSelector:sel]) {
            NSMethodSignature *sig = [vcInstance methodSignatureForSelector:sel];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:vcInstance];
                [inv setSelector:sel];
                
                // 参数1: expire 字符串
                NSString *expire = @"到期时间:2099-12-31 23:59:59";
                [inv setArgument:&expire atIndex:2];
                
                // 参数2: completion block（取地址传递）
                if (completion) {
                    [inv setArgument:&completion atIndex:3];
                    LOG(@"✅ NSInvocation 设置 completion");
                } else {
                    id nilBlock = nil;
                    [inv setArgument:&nilBlock atIndex:3];
                    LOG(@"✅ NSInvocation 设置 nil completion");
                }
                
                [inv invoke];
                LOG(@"✅ showSuccess:completion: 调用成功");
            }
        } else {
            LOG(@"❌ ActVC 没有 showSuccess:completion:");
        }
    } @catch (NSException *e) {
        LOG(@"❌ NSInvocation 调用失败: %@", e.reason);
        // 备用：用 performSelector 传 nil（不传递 block）
        @try {
            [vcInstance performSelector:@selector(showSuccess:completion:) withObject:@"到期时间:2099-12-31 23:59:59" withObject:nil];
            LOG(@"✅ 备用调用成功（nil completion）");
        } @catch (NSException *e2) {
            LOG(@"❌ 备用调用也失败: %@", e2.reason);
        }
    }
    
    // 6. 备用：如果 showSuccess 没触发 dismiss，3秒后手动 dismiss
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([vcInstance isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)vcInstance;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:^{
                        LOG(@"✅ 备用 dismiss 完成");
                    }];
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// Hook 入口
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunV20] v20 NSInvocation版已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWindow();
        
        Class actVC = objc_getClass("WWWActivationViewController");
        if (!actVC) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
        
        // 1. onTapVerify：只记录，不拦截
        Method m = class_getInstanceMethod(actVC, @selector(onTapVerify));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG(@"🎯 [ActVC] onTapVerify 开始（不拦截）");
                id onVerifyBefore = nil;
                @try { onVerifyBefore = [self valueForKey:@"onVerify"]; } @catch (NSException *e) {}
                LOG(@"🌿 onTapVerify 前: onVerify = %@", onVerifyBefore);
                
                ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
                
                id onVerifyAfter = nil;
                @try { onVerifyAfter = [self valueForKey:@"onVerify"]; } @catch (NSException *e) {}
                LOG(@"🌿 onTapVerify 后: onVerify = %@", onVerifyAfter);
                LOG(@"🎯 [ActVC] onTapVerify 结束");
            });
            class_replaceMethod(actVC, @selector(onTapVerify), newIMP, te);
            LOG(@"✅ Hook onTapVerify（只记录）");
        }
        
        // 2. showError:：拦截，改为成功
        m = class_getInstanceMethod(actVC, @selector(showError:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
                LOG(@"🛡️ showError: 拦截 msg = %@", msg);
                naturalBypass(self);
            });
            class_replaceMethod(actVC, @selector(showError:), newIMP, te);
            LOG(@"✅ Hook showError:（→ 成功）");
        }
        
        // 3. isActivated / isVerified
        m = class_getInstanceMethod(actVC, @selector(isActivated));
        if (m) {
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
            class_replaceMethod(actVC, @selector(isActivated), newIMP, te);
            LOG(@"✅ isActivated -> YES");
        }
        
        m = class_getInstanceMethod(actVC, @selector(isVerified));
        if (m) {
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
            class_replaceMethod(actVC, @selector(isVerified), newIMP, te);
            LOG(@"✅ isVerified -> YES");
        }
        
        LOG(@"🚀 v20 初始化完成");
        LOG(@"📋 输入任意15位卡密 → 点验证 → 等3秒看结果");
    });
}
