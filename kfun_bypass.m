#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void swizzleMethod(Class cls, SEL originalSel, SEL newSel)
{
    Method origMethod = class_getInstanceMethod(cls, originalSel);
    Method hookMethod = class_getInstanceMethod(cls, newSel);
    
    if (!origMethod || !hookMethod) return;
    
    BOOL addSuccess = class_addMethod(cls, originalSel, method_getImplementation(hookMethod), method_getTypeEncoding(hookMethod));
    if (addSuccess) {
        class_replaceMethod(cls, newSel, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, hookMethod);
    }
}

@interface WWWActivationHook : NSObject
@end

@implementation WWWActivationHook

- (void)hook_verifyWithCompletion:(void (^)(BOOL success, id data))completion
{
    NSLog(@"[KfunBypass] 拦截 verifyWithCompletion，强制返回验证成功");
    if (completion) {
        completion(YES, @{@"expire":@"2027-12-31"});
    }
}

- (void)hook_activateCode:(NSString *)code completion:(void (^)(BOOL, id))completion
{
    NSLog(@"[KfunBypass] 拦截 activateCode，直接激活成功");
    if(completion) completion(YES, nil);
}

- (BOOL)hook_checkTask
{
    NSLog(@"[KfunBypass] 拦截激活状态检测 → 返回已激活");
    return YES;
}

- (void)hook_onTapVerify
{
    NSLog(@"[KfunBypass] 点击验证按钮，直接走成功流程");
    Class targetCls = NSClassFromString(@"WWWActivationViewController");
    SEL successSel = NSSelectorFromString(@"showSuccess:completion:");
    if([self respondsToSelector:successSel]){
        void (*func)(id, SEL, id, id) = (void (*)(id,SEL,id,id))objc_msgSend;
        func(self, successSel, @{@"expire":@"2027-12-31"}, nil);
    }
}

- (void)hook_showError:(id)err
{
    NSLog(@"[KfunBypass] 屏蔽激活错误弹窗");
    return;
}

@end

// dylib 入口
__attribute__((constructor)) void tweak_init()
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        Class activationCls = NSClassFromString(@"WWWActivation");
        Class activVC = NSClassFromString(@"WWWActivationViewController");
        
        if(activationCls){
            swizzleMethod(activationCls, @selector(verifyWithCompletion:), @selector(hook_verifyWithCompletion:));
            swizzleMethod(activationCls, @selector(activateCode:completion:), @selector(hook_activateCode:completion:));
            swizzleMethod(activationCls, @selector(checkTask), @selector(hook_checkTask));
            NSLog(@"[KfunBypass] WWWActivation 类Hook完成");
        }
        
        if(activVC){
            swizzleMethod(activVC, @selector(onTapVerify), @selector(hook_onTapVerify));
            swizzleMethod(activVC, @selector(showError:), @selector(hook_showError:));
            NSLog(@"[KfunBypass] WWWActivationViewController Hook完成");
        }
        
        if(!activationCls && !activVC){
            NSLog(@"[KfunBypass] ⚠️ 未找到目标类名！二进制类名存在混淆，需要微调字符串");
        }
    });
}
