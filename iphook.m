//
//  iphook.m - KFun Bypass v19 自然版
//  策略：让 App 自己工作，只把"显示错误"改成"显示成功"
//  onTapVerify 不拦截，showError: 拦截并调用 showSuccess:completion:
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
    NSLog(@"[KFunV19] %@", line);
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
        t.text = @"🔍 KFun v19 自然版 (拖动)";
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
        LOG(@"✅ v19 悬浮窗启动");
        LOG(@"🌿 自然版：只改 showError:，让 App 自己走");
    });
}

// ============================================================
// 🌿 自然 bypass：只把"显示错误"改成"显示成功"
// ============================================================
static void naturalBypass(id vcInstance) {
    LOG(@"🌿 自然 bypass 触发：服务器返回错误，改为成功");
    
    // 1. 停止 spinner（onTapVerify 可能已经启动了）
    @try {
        id spinner = [vcInstance valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
            LOG(@"✅ spinner 停止");
        }
    } @catch (NSException *e) {}
    
    // 2. 隐藏错误提示
    @try {
        id errorLabel = [vcInstance valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
            LOG(@"✅ errorLabel 隐藏");
        }
    } @catch (NSException *e) {}
    
    // 3. 移除遮罩（如果有）
    @try {
        id mask = [vcInstance valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
        }
    } @catch (NSException *e) {}
    
    // 4. ⭐ 获取 onVerify completion block（onTapVerify 内部创建的）
    id completion = nil;
    @try {
        completion = [vcInstance valueForKey:@"onVerify"];
        LOG(@"🌿 onVerify completion = %@ (类型: %@)", completion, completion ? NSStringFromClass([completion class]) : @"nil");
    } @catch (NSException *e) {
        LOG(@"⚠️ 获取 onVerify 失败: %@", e.reason);
    }
    
    // 5. ⭐ 调用 showSuccess:completion:，传入 App 自己的 completion
    // 让 App 自己走后续流程（dismiss、设置 MainVC、加载数据等）
    @try {
        if ([vcInstance respondsToSelector:@selector(showSuccess:completion:)]) {
            NSString *expire = @"到期时间:2099-12-31 23:59:59";
            if (completion) {
                [vcInstance performSelector:@selector(showSuccess:completion:) withObject:expire withObject:completion];
                LOG(@"✅ showSuccess:completion: 已调用（使用 App 自己的 completion）");
            } else {
                [vcInstance performSelector:@selector(showSuccess:completion:) withObject:expire withObject:nil];
                LOG(@"✅ showSuccess:completion: 已调用（无 completion）");
            }
        } else {
            LOG(@"❌ ActVC 没有 showSuccess:completion: 方法");
        }
    } @catch (NSException *e) {
        LOG(@"❌ showSuccess:completion: 失败: %@", e.reason);
    }
    
    // 6. 如果上面失败，尝试 buildSuccessViewWithExpire: 作为备用
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            id successView = [vcInstance valueForKey:@"successView"];
            if (!successView || ![successView isKindOfClass:[UIView class]] || ((UIView *)successView).hidden) {
                LOG(@"⚠️ successView 未显示，尝试 buildSuccessViewWithExpire:");
                if ([vcInstance respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
                    [vcInstance performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"到期时间:2099-12-31 23:59:59"];
                    LOG(@"✅ buildSuccessViewWithExpire: 已调用");
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// Hook 入口 - 最小干预
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunV19] v19 自然版已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWindow();
        
        Class actVC = objc_getClass("WWWActivationViewController");
        if (!actVC) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
        
        // 1. ⭐ onTapVerify：只记录，不拦截！让 App 自己发请求
        Method m = class_getInstanceMethod(actVC, @selector(onTapVerify));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG(@"🎯 [ActVC] onTapVerify 开始（不拦截，让 App 自己发请求）");
                // 记录 onVerify 变化
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
            LOG(@"✅ Hook onTapVerify（只记录，不拦截）");
        }
        
        // 2. ⭐ showError:：拦截，改为走成功流程
        m = class_getInstanceMethod(actVC, @selector(showError:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
                LOG(@"🛡️ showError: 拦截（服务器返回错误）msg = %@", msg);
                // 不调用原始的 showError:，改为调用 naturalBypass
                naturalBypass(self);
            });
            class_replaceMethod(actVC, @selector(showError:), newIMP, te);
            LOG(@"✅ Hook showError:（错误→成功）");
        }
        
        // 3. isActivated / isVerified：保险返回 YES
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
        
        LOG(@"🚀 v19 初始化完成");
        LOG(@"📋 操作：输入任意15位卡密 → 点验证 → App 自己发请求 → 我们改错误为成功 → App 自己走后续");
    });
}
