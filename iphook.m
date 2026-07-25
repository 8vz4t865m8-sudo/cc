//
//  iphook.m - KFun 纯 Bypass（随便输入卡密直接进入）
//  目标类: WWWActivation
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

// ============================================================
// 进入主界面（手动操作UI，不依赖任何原生回调）
// ============================================================
static void enterMain(id self) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. 隐藏遮罩层（关键！否则雷达界面被挡住）
        id mask = nil;
        @try { mask = [self valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            LOG(@"authMaskView 已移除");
        }
        
        // 2. 停止按钮转圈
        id verifyBtn = nil;
        @try { verifyBtn = [self valueForKey:@"verifyButton"]; } @catch (NSException *e) {}
        if (verifyBtn) {
            id spinner = nil;
            @try { spinner = [verifyBtn valueForKey:@"spinner"]; } @catch (NSException *e) {}
            if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
                [(UIActivityIndicatorView *)spinner stopAnimating];
            }
        }
        
        // 3. 调用 setupAfterActivation（启动雷达核心逻辑）
        if ([self respondsToSelector:@selector(setupAfterActivation)]) {
            @try {
                [self performSelector:@selector(setupAfterActivation)];
                LOG(@"setupAfterActivation 成功");
            } @catch (NSException *e) {
                LOG(@"setupAfterActivation 失败: %@", e);
            }
        }
        
        // 4. 如果验证页是模态弹窗，直接关掉
        @try {
            if ([self isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)self;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:nil];
                    LOG(@"验证页已 dismiss");
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// Hook 1: onTapVerify（按钮点击，最高优先级）
// ============================================================
static void hook_onTapVerify(id self, SEL _cmd) {
    LOG(@"🎯 onTapVerify 被拦截，直接放行");
    
    // 不管输入框里是什么，直接显示成功
    if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
        @try {
            [self performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
        } @catch (NSException *e) {}
    }
    
    // 延迟 0.5 秒进入主界面（给成功动画一点时间）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        enterMain(self);
    });
}

// ============================================================
// Hook 2: activateCode:completion:（代码调用入口）
// ⚠️ 不调用原生的 completion，避免 block 签名闪退/卡死
// ============================================================
static void hook_activateCode(id self, SEL _cmd, NSString *code, id completion) {
    LOG(@"🎯 activateCode: 被拦截，code=%@", code);
    
    if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
        @try {
            [self performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
        } @catch (NSException *e) {}
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        enterMain(self);
    });
    
    // ❌ 不调用原生的 completion(id)，避免签名不匹配
}

// ============================================================
// Hook 3: verifyWithCompletion:（启动时自动验证）
// ============================================================
static void hook_verifyWithCompletion(id self, SEL _cmd, id completion) {
    LOG(@"🎯 verifyWithCompletion: 被拦截");
    
    if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
        @try {
            [self performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
        } @catch (NSException *e) {}
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        enterMain(self);
    });
    
    // ❌ 不调用 completion
}

// ============================================================
// Hook 4: showError:（拦截错误提示）
// ============================================================
static void hook_showError(id self, SEL _cmd, NSString *msg) {
    LOG(@"🛡️ showError 被拦截: %@", msg);
    // 不显示错误，直接成功
    enterMain(self);
}

// ============================================================
// Hook 5: checkTask / shakeField（禁用过期检查和抖动）
// ============================================================
static void hook_checkTask(id self, SEL _cmd) {
    LOG(@"🛡️ checkTask 被拦截");
}
static void hook_shakeField(id self, SEL _cmd) {
    LOG(@"🛡️ shakeField 被拦截");
}

// ============================================================
// Hook 6: isActivated / isVerified（永远返回 YES）
// ============================================================
static BOOL hook_isActivated(id self, SEL _cmd) {
    return YES;
}

// ============================================================
// 安装 Hook
// ============================================================
static void installHooks() {
    Class cls = objc_getClass("WWWActivation");
    if (!cls) {
        LOG(@"❌ 找不到 WWWActivation!");
        return;
    }
    LOG(@"✅ 找到类: WWWActivation");
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) { method_setImplementation(m, (IMP)hook_onTapVerify); LOG(@"✅ onTapVerify"); }
    
    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) { method_setImplementation(m, (IMP)hook_activateCode); LOG(@"✅ activateCode:completion:"); }
    
    m = class_getInstanceMethod(cls, @selector(verifyWithCompletion:));
    if (m) { method_setImplementation(m, (IMP)hook_verifyWithCompletion); LOG(@"✅ verifyWithCompletion:"); }
    
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) { method_setImplementation(m, (IMP)hook_showError); LOG(@"✅ showError:"); }
    
    m = class_getInstanceMethod(cls, @selector(checkTask));
    if (m) { method_setImplementation(m, (IMP)hook_checkTask); LOG(@"✅ checkTask"); }
    
    m = class_getInstanceMethod(cls, @selector(shakeField));
    if (m) { method_setImplementation(m, (IMP)hook_shakeField); LOG(@"✅ shakeField"); }
    
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) { method_setImplementation(m, (IMP)hook_isActivated); LOG(@"✅ isActivated"); }
    else {
        m = class_getInstanceMethod(cls, @selector(isVerified));
        if (m) { method_setImplementation(m, (IMP)hook_isActivated); LOG(@"✅ isVerified"); }
    }
    
    LOG(@"🚀 全部 Hook 完成");
}

__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun Bypass 极简版已加载");
    LOG(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        installHooks();
    });
}
