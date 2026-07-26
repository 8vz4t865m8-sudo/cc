//
//  iphook.m - KFun 全自动 Bypass（打开 App 2 秒后自动进入）
//  不依赖任何类名/方法名，通过特征识别验证界面
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

// ============================================================
// 核心 bypass：强制移除遮罩 + 停止转圈 + 进入主界面
// ============================================================
static void forceBypass(id target) {
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // 1. 停止所有 ActivityIndicatorView 的转圈
        if ([target isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)target;
            for (UIView *subview in vc.view.subviews) {
                if ([subview isKindOfClass:[UIActivityIndicatorView class]]) {
                    [(UIActivityIndicatorView *)subview stopAnimating];
                    subview.hidden = YES;
                    LOG(@"停止转圈");
                }
            }
            // 递归停止子视图中的转圈
            void (^stopAllSpinners)(UIView *) = ^(UIView *view) {
                for (UIView *v in view.subviews) {
                    if ([v isKindOfClass:[UIActivityIndicatorView class]]) {
                        [(UIActivityIndicatorView *)v stopAnimating];
                        v.hidden = YES;
                    }
                    stopAllSpinners(v);
                }
            };
            stopAllSpinners(vc.view);
        }
        
        // 2. 通过 KVC 尝试获取并隐藏 authMaskView
        id mask = nil;
        @try { mask = [target valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            LOG(@"authMaskView 已移除");
        }
        
        // 3. 隐藏 errorLabel
        id errorLabel = nil;
        @try { errorLabel = [target valueForKey:@"errorLabel"]; } @catch (NSException *e) {}
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
        
        // 4. 隐藏 successView
        id successView = nil;
        @try { successView = [target valueForKey:@"successView"]; } @catch (NSException *e) {}
        if (successView && [successView isKindOfClass:[UIView class]]) {
            [(UIView *)successView setHidden:YES];
            [(UIView *)successView removeFromSuperview];
        }
        
        // 5. 调用 buildSuccessViewWithExpire:（如果存在）
        if ([target respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            @try {
                [target performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
                LOG(@"buildSuccessViewWithExpire: 已调用");
            } @catch (NSException *e) {}
        }
        
        // 6. 调用 setupAfterActivation（关键：启动雷达核心逻辑）
        if ([target respondsToSelector:@selector(setupAfterActivation)]) {
            @try {
                [target performSelector:@selector(setupAfterActivation)];
                LOG(@"setupAfterActivation 已调用，雷达应该启动了");
            } @catch (NSException *e) {
                LOG(@"setupAfterActivation 失败: %@", e);
            }
        }
        
        // 7. 尝试关闭验证弹窗
        @try {
            if ([target isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)target;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:nil];
                    LOG(@"验证弹窗已关闭");
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// Hook 1: 拦截所有按钮点击（保险机制）
// ============================================================
static BOOL (*orig_sendAction)(id, SEL, SEL, id, id, UIEvent *);

static BOOL hook_sendAction(id self, SEL _cmd, SEL action, id target, id sender, UIEvent *event) {
    NSString *actionName = NSStringFromSelector(action);
    
    // 如果点击的是验证相关按钮，直接 bypass
    if ([actionName rangeOfString:@"Verify" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [actionName rangeOfString:@"verify" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [actionName rangeOfString:@"activate" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [actionName rangeOfString:@"tap" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [actionName rangeOfString:@"submit" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [actionName rangeOfString:@"confirm" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [actionName rangeOfString:@"login" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        
        LOG(@"🎯 拦截按钮点击: %@, target=%@", actionName, target);
        forceBypass(target);
        return YES; // 吃掉事件，不让原生处理
    }
    
    return orig_sendAction(self, _cmd, action, target, sender, event);
}

// ============================================================
// Hook 2: 验证界面出现时自动 bypass（主要机制）
// ============================================================
static void (*orig_viewDidAppear)(id, SEL, BOOL);

static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    // 检查这个 VC 是否有验证界面的特征（authMaskView 或 codeField）
    id mask = nil;
    @try { mask = [self valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
    id codeField = nil;
    @try { codeField = [self valueForKey:@"codeField"]; } @catch (NSException *e) {}
    id verifyBtn = nil;
    @try { verifyBtn = [self valueForKey:@"verifyButton"]; } @catch (NSException *e) {}
    
    if (mask || codeField || verifyBtn) {
        LOG(@"🎯 检测到验证界面: %@, 2秒后自动 bypass", NSStringFromClass([self class]));
        
        // 延迟 2 秒，等界面完全加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            forceBypass(self);
        });
    }
}

// ============================================================
// Hook 3: 定时轮询（兜底机制）
// ============================================================
static void startPolling() {
    [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *timer) {
        // 遍历所有窗口
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            UIViewController *topVC = window.rootViewController;
            // 找到最上层的 presentedViewController
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
            
            // 检查是否是验证界面
            id mask = nil;
            @try { mask = [topVC valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
            id codeField = nil;
            @try { codeField = [topVC valueForKey:@"codeField"]; } @catch (NSException *e) {}
            
            if (mask || codeField) {
                LOG(@"🎯 轮询检测到验证界面，自动 bypass");
                forceBypass(topVC);
                return;
            }
        }
    }];
    LOG(@"✅ 轮询已启动");
}

// ============================================================
// 初始化
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun 全自动 Bypass 已加载");
    LOG(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // 1. Hook UIApplication sendAction（拦截按钮点击）
        Class appClass = [UIApplication class];
        Method m1 = class_getInstanceMethod(appClass, @selector(sendAction:to:from:forEvent:));
        if (m1) {
            orig_sendAction = (BOOL (*)(id, SEL, SEL, id, id, UIEvent *))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_sendAction);
            LOG(@"✅ sendAction 已 hook");
        }
        
        // 2. Hook UIViewController viewDidAppear（界面出现时自动 bypass）
        Class vcClass = [UIViewController class];
        Method m2 = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
        if (m2) {
            orig_viewDidAppear = (void (*)(id, SEL, BOOL))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_viewDidAppear);
            LOG(@"✅ viewDidAppear 已 hook");
        }
        
        // 3. 启动轮询
        startPolling();
        
        LOG(@"🚀 全部就绪，打开验证界面后 2 秒自动进入");
    });
}
