//
//  iphook.m - KFun Bypass 精准版
//  只 hook WWWActivation 类，不碰系统类，模拟完整验证流程
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

// 模拟完整验证成功流程
static void simulateSuccess(id self) {
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // 1. 停止转圈
        id spinner = nil;
        @try { spinner = [self valueForKey:@"spinner"]; } @catch (NSException *e) {}
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
            LOG(@"转圈已停止");
        }
        
        // 2. 关闭 loading 状态
        if ([self respondsToSelector:@selector(setLoading:)]) {
            @try { [self performSelector:@selector(setLoading:) withObject:@NO]; } @catch (NSException *e) {}
        }
        
        // 3. 隐藏错误提示
        id errorLabel = nil;
        @try { errorLabel = [self valueForKey:@"errorLabel"]; } @catch (NSException *e) {}
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
        
        // 4. 显示成功弹窗（带过期时间）—— 这是关键！
        if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            @try {
                [self performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
                LOG(@"✅ 成功弹窗已显示");
            } @catch (NSException *e) {
                LOG(@"buildSuccessViewWithExpire: 失败: %@", e);
            }
        }
        
        // 5. 延迟 2 秒，等成功弹窗自带的定时器触发进入主界面
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            LOG(@"🚀 尝试进入主界面...");
            
            // 尝试关闭验证界面（各种方式）
            @try {
                if ([self isKindOfClass:[UIViewController class]]) {
                    UIViewController *vc = (UIViewController *)self;
                    
                    // 方式1：如果是 present 出来的，dismiss
                    if (vc.presentingViewController) {
                        [vc dismissViewControllerAnimated:NO completion:nil];
                        LOG(@"验证界面已 dismiss");
                    }
                    // 方式2：如果在导航栈里，pop
                    else if (vc.navigationController) {
                        [vc.navigationController popViewControllerAnimated:NO];
                        LOG(@"验证界面已 pop");
                    }
                    // 方式3：从父视图移除
                    else {
                        [vc.view removeFromSuperview];
                        LOG(@"验证界面视图已移除");
                    }
                }
            } @catch (NSException *e) {}
            
            // 6. 尝试启动雷达核心逻辑
            if ([self respondsToSelector:@selector(setupAfterActivation)]) {
                @try {
                    [self performSelector:@selector(setupAfterActivation)];
                    LOG(@"✅ setupAfterActivation 已调用，雷达启动");
                } @catch (NSException *e) {
                    LOG(@"setupAfterActivation 失败: %@", e);
                }
            }
        });
    });
}

// Hook viewDidLoad —— 验证界面创建时自动触发
static void hook_viewDidLoad(id self, SEL _cmd) {
    // 调用原方法
    struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&super, _cmd);
    
    LOG(@"🎯 viewDidLoad 触发，自动模拟验证成功");
    simulateSuccess(self);
}

// Hook viewDidAppear —— 验证界面显示时触发（备用）
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
    ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&super, _cmd, animated);
    
    LOG(@"🎯 viewDidAppear 触发");
    simulateSuccess(self);
}

// Hook onTapVerify —— 如果用户手动点击验证按钮
static void hook_onTapVerify(id self, SEL _cmd) {
    LOG(@"🎯 onTapVerify 被拦截");
    simulateSuccess(self);
}

// Hook activateCode:completion: —— 代码调用入口
static void hook_activateCode(id self, SEL _cmd, NSString *code, id completion) {
    LOG(@"🎯 activateCode: 被拦截");
    simulateSuccess(self);
    // ❌ 不调用原生的 completion，避免 block 签名问题
}

// 安装 Hook
static void installHook(Class cls) {
    if (!cls) return;
    LOG(@"✅ 找到类: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        method_setImplementation(m, (IMP)hook_viewDidLoad);
        LOG(@"✅ Hooked viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        method_setImplementation(m, (IMP)hook_viewDidAppear);
        LOG(@"✅ Hooked viewDidAppear");
    }
    
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        method_setImplementation(m, (IMP)hook_onTapVerify);
        LOG(@"✅ Hooked onTapVerify");
    }
    
    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) {
        method_setImplementation(m, (IMP)hook_activateCode);
        LOG(@"✅ Hooked activateCode:");
    }
    
    LOG(@"🚀 Hook 安装完成，等待验证界面出现...");
}

__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun Bypass 精准版已加载");
    LOG(@"========================================");
    
    // 延迟 0.3 秒等类加载
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // 尝试 WWWActivation
        Class cls = objc_getClass("WWWActivation");
        if (!cls) cls = objc_getClass("WWWActivationViewController");
        
        if (cls) {
            installHook(cls);
        } else {
            LOG(@"⚠️ 未找到验证类，1秒后重试...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                Class cls2 = objc_getClass("WWWActivation");
                if (!cls2) cls2 = objc_getClass("WWWActivationViewController");
                installHook(cls2);
            });
        }
    });
}
