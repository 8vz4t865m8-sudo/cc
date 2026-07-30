// kfun_crack.m - kfun activation bypass dylib
// Hooks WWWActivation and WWWActivationViewController
// Any code accepted, no network request, no server needed

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================================
#pragma mark - Activation Stamp
// ============================================================

static void writeActivationStamp(void) {
    NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *stampPath = [docDir stringByAppendingPathComponent:@"www_activation_stamp.plist"];
    
    // 10年有效期
    NSDate *expireDate = [NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10];
    
    NSDictionary *stamp = @{
        @"activated": @YES,
        @"expire": expireDate,
        @"code": @"LOCAL-CRACK-OK",
        @"timestamp": [NSDate date],
        @"machine": @"bypassed",
    };
    
    [stamp writeToFile:stampPath atomically:YES];
    NSLog(@"[kfun_crack] stamp written -> %@", stampPath);
}

static NSString *fakeExpireString(void) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd"];
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10]];
}

// ============================================================
#pragma mark - WWWActivation hooks
// ============================================================

// - (void)activateCode:(NSString *)code completion:(void(^)(BOOL, NSString*, id))completion
static void hook_activateCode_completion(id self, SEL _cmd, NSString *code, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[kfun_crack] activateCode:\"%@\" -> forced success", code);
    writeActivationStamp();
    if (completion) {
        completion(YES, fakeExpireString(), nil);
    }
}

// - (NSString *)activationStampPath
static NSString *hook_activationStampPath(id self, SEL _cmd) {
    NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docDir stringByAppendingPathComponent:@"www_activation_stamp.plist"];
}

// - (void)checkTask
static void hook_checkTask(id self, SEL _cmd) {
    NSLog(@"[kfun_crack] checkTask -> skipped");
}

// - (void)verifyWithCompletion:(void(^)(BOOL, NSString*, id))completion
static void hook_verifyWithCompletion(id self, SEL _cmd, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[kfun_crack] verifyWithCompletion -> forced success");
    writeActivationStamp();
    if (completion) {
        completion(YES, fakeExpireString(), nil);
    }
}

// ============================================================
#pragma mark - WWWActivationViewController hooks
// ============================================================

// - (void)onTapVerify
static void hook_onTapVerify(id self, SEL _cmd) {
    NSLog(@"[kfun_crack] onTapVerify -> auto-success");
    writeActivationStamp();
    
    // 获取 onVerify block 并调用
    IVar onVerifyIvar = class_getInstanceVariable([self class], "_onVerify");
    if (onVerifyIvar) {
        ptrdiff_t offset = ivar_getOffset(onVerifyIvar);
        void (^onVerify)(void) = *((__strong id *)((char *)(__bridge void *)self + offset));
        if (onVerify) {
            onVerify();
        }
    }
    
    // 隐藏 authMaskView
    IVar maskIvar = class_getInstanceVariable([self class], "_authMaskView");
    if (maskIvar) {
        ptrdiff_t offset = ivar_getOffset(maskIvar);
        UIView *mask = *((__strong UIView **)((char *)(__bridge void *)self + offset));
        if (mask) {
            dispatch_async(dispatch_get_main_queue(), ^{
                mask.hidden = YES;
                [mask removeFromSuperview];
            });
        }
    }
    
    // 调用 buildSuccessViewWithExpire:
    SEL buildSel = NSSelectorFromString(@"buildSuccessViewWithExpire:");
    if ([self respondsToSelector:buildSel]) {
        NSString *expireStr = fakeExpireString();
        NSMethodSignature *sig = [self methodSignatureForSelector:buildSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:self];
        [inv setSelector:buildSel];
        [inv setArgument:&expireStr atIndex:2];
        [inv invoke];
    }
}

// - (void)showSuccess:(BOOL)success completion:(void(^)(void))completion
static void hook_showSuccess_completion(id self, SEL _cmd, BOOL success, void (^completion)(void)) {
    NSLog(@"[kfun_crack] showSuccess -> forced YES");
    writeActivationStamp();
    
    // 隐藏 authMaskView
    IVar maskIvar = class_getInstanceVariable([self class], "_authMaskView");
    if (maskIvar) {
        ptrdiff_t offset = ivar_getOffset(maskIvar);
        UIView *mask = *((__strong UIView **)((char *)(__bridge void *)self + offset));
        if (mask) {
            dispatch_async(dispatch_get_main_queue(), ^{
                mask.hidden = YES;
                [mask removeFromSuperview];
            });
        }
    }
    
    SEL buildSel = NSSelectorFromString(@"buildSuccessViewWithExpire:");
    if ([self respondsToSelector:buildSel]) {
        NSString *expireStr = fakeExpireString();
        NSMethodSignature *sig = [self methodSignatureForSelector:buildSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:self];
        [inv setSelector:buildSel];
        [inv setArgument:&expireStr atIndex:2];
        [inv invoke];
    }
    
    if (completion) {
        completion();
    }
}

// ============================================================
#pragma mark - Auto-dismiss activation screen
// ============================================================

static IMP orig_viewDidLoad = NULL;

static void hook_viewDidLoad(id self, SEL _cmd) {
    Class cls = [self class];
    SEL sel = @selector(viewDidLoad);
    
    // Call original via saved IMP
    if (orig_viewDidLoad) {
        ((void (*)(id, SEL))orig_viewDidLoad)(self, sel);
    }
    
    NSLog(@"[kfun_crack] WWWActivationViewController viewDidLoad -> auto-dismiss");
    
    // Write stamp
    writeActivationStamp();
    
    // Auto-dismiss after 0.3s
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Hide auth mask
        IVar maskIvar = class_getInstanceVariable(cls, "_authMaskView");
        if (maskIvar) {
            ptrdiff_t offset = ivar_getOffset(maskIvar);
            UIView *mask = *((__strong UIView **)((char *)(__bridge void *)self + offset));
            if (mask) {
                mask.hidden = YES;
                [mask removeFromSuperview];
            }
        }
        
        // Build success view
        SEL buildSel = NSSelectorFromString(@"buildSuccessViewWithExpire:");
        if ([self respondsToSelector:buildSel]) {
            NSString *expireStr = fakeExpireString();
            NSMethodSignature *sig = [self methodSignatureForSelector:buildSel];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:self];
            [inv setSelector:buildSel];
            [inv setArgument:&expireStr atIndex:2];
            [inv invoke];
        }
        
        // Dismiss VC
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

// ============================================================
#pragma mark - Helper: safe swizzle
// ============================================================

static BOOL swizzleInstanceMethod(Class cls, SEL sel, IMP newImp, const char *typeEncoding) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[kfun_crack] WARN: method '%@' not found on %@", NSStringFromSelector(sel), cls);
        return NO;
    }
    if (typeEncoding) {
        // Add method with new implementation (in case the class doesn't own it)
        class_addMethod(cls, sel, newImp, typeEncoding);
    }
    method_setImplementation(m, newImp);
    NSLog(@"[kfun_crack] OK: hooked -[%@ %@]", cls, NSStringFromSelector(sel));
    return YES;
}

// ============================================================
#pragma mark - Constructor
// ============================================================

__attribute__((constructor))
static void kfun_crack_init(void) {
    NSLog(@"[kfun_crack] ========== dylib loaded ==========");
    
    // 延迟 1 秒等 ObjC runtime 就绪
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // ---- Hook WWWActivation ----
        Class actCls = objc_getClass("WWWActivation");
        if (actCls) {
            NSLog(@"[kfun_crack] Found WWWActivation");
            
            swizzleInstanceMethod(actCls,
                NSSelectorFromString(@"activateCode:completion:"),
                (IMP)hook_activateCode_completion,
                "v@:@@?");
            
            swizzleInstanceMethod(actCls,
                NSSelectorFromString(@"activationStampPath"),
                (IMP)hook_activationStampPath,
                "@@:");
            
            swizzleInstanceMethod(actCls,
                NSSelectorFromString(@"checkTask"),
                (IMP)hook_checkTask,
                "v@:");
            
            swizzleInstanceMethod(actCls,
                NSSelectorFromString(@"verifyWithCompletion:"),
                (IMP)hook_verifyWithCompletion,
                "v@:@?");
        } else {
            NSLog(@"[kfun_crack] WARN: WWWActivation class not found");
        }
        
        // ---- Hook WWWActivationViewController ----
        Class vcCls = objc_getClass("WWWActivationViewController");
        if (vcCls) {
            NSLog(@"[kfun_crack] Found WWWActivationViewController");
            
            swizzleInstanceMethod(vcCls,
                NSSelectorFromString(@"onTapVerify"),
                (IMP)hook_onTapVerify,
                "v@:");
            
            swizzleInstanceMethod(vcCls,
                NSSelectorFromString(@"showSuccess:completion:"),
                (IMP)hook_showSuccess_completion,
                "v@:B@?");
            
            // Hook viewDidLoad for auto-dismiss
            Method vdM = class_getInstanceMethod(vcCls, @selector(viewDidLoad));
            if (vdM) {
                orig_viewDidLoad = method_getImplementation(vdM);
                method_setImplementation(vdM, (IMP)hook_viewDidLoad);
                NSLog(@"[kfun_crack] OK: hooked -[WWWActivationViewController viewDidLoad]");
            }
        } else {
            NSLog(@"[kfun_crack] WARN: WWWActivationViewController class not found");
        }
        
        // 写入初始激活标记
        writeActivationStamp();
        
        NSLog(@"[kfun_crack] ========== all hooks installed ==========");
    });
}
