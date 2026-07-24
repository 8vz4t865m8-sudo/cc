//
//  iphook.m - KFun 卡密验证 Bypass (最简版)
//  策略: 只 Hook showError:，让错误提示变成成功，然后移除遮罩进入主界面
//  不 Hook onTapVerify 和 activateCode，让原逻辑正常走
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

static void hideMaskAndEnterMain(id self) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 隐藏遮罩
        id mask = nil;
        @try { mask = [self valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
        if (mask) {
            [mask setValue:@YES forKey:@"hidden"];
            [(UIView *)mask setUserInteractionEnabled:NO];
            [(UIView *)mask removeFromSuperview];
        }
        // 隐藏错误标签
        id errorLabel = nil;
        @try { errorLabel = [self valueForKey:@"errorLabel"]; } @catch (NSException *e) {}
        if (errorLabel) {
            [errorLabel setValue:@"" forKey:@"text"];
            [(UIView *)errorLabel setHidden:YES];
        }
        // 尝试进入主界面
        if ([self respondsToSelector:@selector(setupAfterActivation)]) {
            ((void(*)(id, SEL))objc_msgSend)(self, @selector(setupAfterActivation));
        }
    });
}

static void hook_showError(id self, SEL _cmd, NSString *msg) {
    LOG(@"拦截错误: %@，直接放行", msg);
    // 不显示错误，直接移除遮罩进入主界面
    hideMaskAndEnterMain(self);
}

static void hook_activateCode(id self, SEL _cmd, NSString *code, void (^completion)(BOOL success, id data)) {
    LOG(@"Bypass activateCode: %@", code);
    // 直接回调成功
    if (completion) {
        completion(YES, @{
            @"code": @0,
            @"msg": @"success",
            @"data": @{
                @"expire": @"2099-12-31 23:59:59",
                @"type": @"lifetime"
            }
        });
    }
    // 延迟移除遮罩
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        hideMaskAndEnterMain(self);
    });
}

static void hook_onTapVerify(id self, SEL _cmd) {
    LOG(@"Bypass onTapVerify");
    // 直接显示成功弹窗
    if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
        ((void(*)(id, SEL, NSString *))objc_msgSend)(self, @selector(buildSuccessViewWithExpire:), @"2099-12-31 23:59:59");
    }
    // 延迟移除遮罩进入主界面
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        hideMaskAndEnterMain(self);
    });
}

static void hook_checkTask(id self, SEL _cmd) {
    // 空实现
}

static void hook_shakeField(id self, SEL _cmd) {
    // 空实现
}

static void doInit() {
    LOG(@"开始 Hook...");
    Class cls = objc_getClass("WWWActivationViewController");
    if (!cls) { LOG(@"找不到类!"); return; }
    
    Method m;
    
    // 只 Hook showError:，让任何错误都变成放行
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) { method_setImplementation(m, (IMP)hook_showError); LOG(@"Hooked showError:"); }
    
    // Hook activateCode:completion: 作为备用
    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) { method_setImplementation(m, (IMP)hook_activateCode); LOG(@"Hooked activateCode:completion:"); }
    
    // Hook onTapVerify 作为备用
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) { method_setImplementation(m, (IMP)hook_onTapVerify); LOG(@"Hooked onTapVerify"); }
    
    // Hook checkTask 和 shakeField
    m = class_getInstanceMethod(cls, @selector(checkTask));
    if (m) { method_setImplementation(m, (IMP)hook_checkTask); LOG(@"Hooked checkTask"); }
    
    m = class_getInstanceMethod(cls, @selector(shakeField));
    if (m) { method_setImplementation(m, (IMP)hook_shakeField); LOG(@"Hooked shakeField"); }
    
    LOG(@"初始化完成");
}

__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun Bypass 已加载");
    LOG(@"========================================");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        doInit();
    });
}
