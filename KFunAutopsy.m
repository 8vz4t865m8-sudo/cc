// KFunAutopsy.m - kfun activation bypass dylib
// Hooks WWWActivation and WWWActivationViewController
// Any code accepted, no network request, no server needed

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>

// ============================================================
#pragma mark - Activation Stamp
// ============================================================

static void writeActivationStamp(void) {
    NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *stampPath = [docDir stringByAppendingPathComponent:@"www_activation_stamp.plist"];

    NSDate *expireDate = [NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10];

    NSDictionary *stamp = @{
        @"activated": @YES,
        @"expire": expireDate,
        @"code": @"LOCAL-CRACK-OK",
        @"timestamp": [NSDate date],
        @"machine": @"bypassed",
    };

    [stamp writeToFile:stampPath atomically:YES];
    NSLog(@"[KFunAutopsy] stamp written -> %@", stampPath);
}

static NSString *fakeExpireString(void) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd"];
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10]];
}

// ============================================================
#pragma mark - ivar helpers (ARC-safe via memcpy)
// ============================================================

static id readIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return nil;
    ptrdiff_t off = ivar_getOffset(iv);
    id value = nil;
    memcpy(&value, (const char *)(__bridge void *)obj + off, sizeof(value));
    return value;
}

static void hideAuthMask(id obj) {
    UIView *mask = (UIView *)readIvar(obj, "_authMaskView");
    if (mask) {
        UIView *keep = mask;
        dispatch_async(dispatch_get_main_queue(), ^{
            keep.hidden = YES;
            [keep removeFromSuperview];
        });
    }
}

static void callBuildSuccess(id obj) {
    SEL sel = NSSelectorFromString(@"buildSuccessViewWithExpire:");
    if (![obj respondsToSelector:sel]) return;
    NSString *exp = fakeExpireString();
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];
    [inv setArgument:&exp atIndex:2];
    [inv invoke];
}

// ============================================================
#pragma mark - WWWActivation hooks
// ============================================================

static void hook_activateCode_completion(id self, SEL _cmd, NSString *code, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[KFunAutopsy] activateCode:\"%@\" -> forced success", code);
    writeActivationStamp();
    if (completion) completion(YES, fakeExpireString(), nil);
}

static NSString *hook_activationStampPath(id self, SEL _cmd) {
    NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docDir stringByAppendingPathComponent:@"www_activation_stamp.plist"];
}

static void hook_checkTask(id self, SEL _cmd) {
    NSLog(@"[KFunAutopsy] checkTask -> skipped");
}

static void hook_verifyWithCompletion(id self, SEL _cmd, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[KFunAutopsy] verifyWithCompletion -> forced success");
    writeActivationStamp();
    if (completion) completion(YES, fakeExpireString(), nil);
}

// ============================================================
#pragma mark - WWWActivationViewController hooks
// ============================================================

static void hook_onTapVerify(id self, SEL _cmd) {
    NSLog(@"[KFunAutopsy] onTapVerify -> auto-success");
    writeActivationStamp();

    // 调用 onVerify block
    void (^onVerify)(void) = (void (^)(void))readIvar(self, "_onVerify");
    if (onVerify) onVerify();

    hideAuthMask(self);
    callBuildSuccess(self);
}

static void hook_showSuccess_completion(id self, SEL _cmd, BOOL success, void (^completion)(void)) {
    NSLog(@"[KFunAutopsy] showSuccess -> forced YES");
    writeActivationStamp();
    hideAuthMask(self);
    callBuildSuccess(self);
    if (completion) completion();
}

// ============================================================
#pragma mark - Auto-dismiss activation screen
// ============================================================

static IMP orig_viewDidLoad = NULL;

static void hook_viewDidLoad(id self, SEL _cmd) {
    if (orig_viewDidLoad) {
        ((void (*)(id, SEL))orig_viewDidLoad)(self, _cmd);
    }

    NSLog(@"[KFunAutopsy] WWWActivationViewController viewDidLoad -> auto-dismiss");
    writeActivationStamp();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        hideAuthMask(self);
        callBuildSuccess(self);
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

// ============================================================
#pragma mark - Helper: safe swizzle
// ============================================================

static BOOL swizzleInstanceMethod(Class cls, SEL sel, IMP newImp, const char *typeEncoding) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[KFunAutopsy] WARN: method '%@' not found on %@", NSStringFromSelector(sel), cls);
        return NO;
    }
    if (typeEncoding) {
        class_addMethod(cls, sel, newImp, typeEncoding);
    }
    method_setImplementation(m, newImp);
    NSLog(@"[KFunAutopsy] OK: hooked -[%@ %@]", cls, NSStringFromSelector(sel));
    return YES;
}

// ============================================================
#pragma mark - Constructor
// ============================================================

__attribute__((constructor))
static void KFunAutopsy_init(void) {
    NSLog(@"[KFunAutopsy] ========== dylib loaded ==========");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        // ---- Hook WWWActivation ----
        Class actCls = objc_getClass("WWWActivation");
        if (actCls) {
            NSLog(@"[KFunAutopsy] Found WWWActivation");

            swizzleInstanceMethod(actCls,
                NSSelectorFromString(@"activateCode:completion:"),
                (IMP)hook_activateCode_completion, "v@:@@?");

            swizzleInstanceMethod(actCls,
                NSSelectorFromString(@"activationStampPath"),
                (IMP)hook_activationStampPath, "@@:");

            swizzleInstanceMethod(actCls,
                NSSelectorFromString(@"checkTask"),
                (IMP)hook_checkTask, "v@:");

            swizzleInstanceMethod(actCls,
                NSSelectorFromString(@"verifyWithCompletion:"),
                (IMP)hook_verifyWithCompletion, "v@:@?");
        } else {
            NSLog(@"[KFunAutopsy] WARN: WWWActivation class not found");
        }

        // ---- Hook WWWActivationViewController ----
        Class vcCls = objc_getClass("WWWActivationViewController");
        if (vcCls) {
            NSLog(@"[KFunAutopsy] Found WWWActivationViewController");

            swizzleInstanceMethod(vcCls,
                NSSelectorFromString(@"onTapVerify"),
                (IMP)hook_onTapVerify, "v@:");

            swizzleInstanceMethod(vcCls,
                NSSelectorFromString(@"showSuccess:completion:"),
                (IMP)hook_showSuccess_completion, "v@:B@?");

            Method vdM = class_getInstanceMethod(vcCls, @selector(viewDidLoad));
            if (vdM) {
                orig_viewDidLoad = method_getImplementation(vdM);
                method_setImplementation(vdM, (IMP)hook_viewDidLoad);
                NSLog(@"[KFunAutopsy] OK: hooked -[WWWActivationViewController viewDidLoad]");
            }
        } else {
            NSLog(@"[KFunAutopsy] WARN: WWWActivationViewController class not found");
        }

        writeActivationStamp();
        NSLog(@"[KFunAutopsy] ========== all hooks installed ==========");
    });
}
