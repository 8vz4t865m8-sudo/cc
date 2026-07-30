// KFunAutopsy.m - kfun activation bypass (view-level approach)
// 不 hook 任何业务方法，只在 VC 层面跳过激活界面
// 避免和混淆代码冲突

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================================
#pragma mark - Activation stamp
// ============================================================

static void writeStamp(void) {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [doc stringByAppendingPathComponent:@"www_activation_stamp.plist"];
    [@{
        @"activated": @YES,
        @"expire": [NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10],
        @"code": @"BYPASS",
        @"timestamp": [NSDate date],
    } writeToFile:path atomically:YES];
    NSLog(@"[KFun] stamp written");
}

// ============================================================
#pragma mark - Hook: WWWActivationViewController
// ============================================================

// 保存原始 IMP
static IMP orig_viewDidLoad = NULL;
static IMP orig_viewDidAppear = NULL;
static IMP orig_onTapVerify = NULL;

// viewDidLoad: 写入激活标记，尝试跳过激活检查
static void hook_viewDidLoad(id self, SEL _cmd) {
    // 先写入激活标记
    writeStamp();

    // 调用原始 viewDidLoad
    if (orig_viewDidLoad) {
        ((void (*)(id, SEL))orig_viewDidLoad)(self, _cmd);
    }

    NSLog(@"[KFun] WWWActivationViewController.viewDidLoad hooked");
}

// viewDidAppear: 0.5秒后自动消失
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    // 调用原始 viewDidAppear
    if (orig_viewDidAppear) {
        ((void (*)(id, SEL, BOOL))orig_viewDidAppear)(self, _cmd, animated);
    }

    NSLog(@"[KFun] WWWActivationViewController.viewDidAppear -> auto-dismiss");

    // 延迟 0.5 秒后 dismiss
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        writeStamp();
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

// onTapVerify: 不调用原始方法（避免触发混淆代码），直接写标记 + dismiss
static void hook_onTapVerify(id self, SEL _cmd) {
    NSLog(@"[KFun] onTapVerify -> bypassed (no original call)");
    writeStamp();

    // 直接 dismiss，不调用原始 onTapVerify
    [self dismissViewControllerAnimated:YES completion:nil];
}

// ============================================================
#pragma mark - Hook: WWWActivation (激活逻辑类)
// ============================================================

static IMP orig_activateCode = NULL;
static IMP orig_stampPath = NULL;
static IMP orig_checkTask = NULL;
static IMP orig_verifyCompletion = NULL;

// activateCode:completion: — 调用原始方法，但替换 completion block
static void hook_activateCode(id self, SEL _cmd, NSString *code, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[KFun] activateCode:\"%@\" -> wrapping completion", code);
    writeStamp();

    // 创建一个替换的 completion block，总是返回成功
    void (^safeCompletion)(BOOL, NSString *, id) = ^(BOOL success, NSString *expire, id error) {
        NSLog(@"[KFun] completion called with success=%d -> forced YES", success);
        writeStamp();
        if (completion) {
            // 总是传成功
            NSDateFormatter *f = [[NSDateFormatter alloc] init];
            [f setDateFormat:@"yyyy-MM-dd"];
            NSString *fakeExpire = [f stringFromDate:
                [NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10]];
            completion(YES, fakeExpire, nil);
        }
    };

    // 调用原始方法，但用替换的 completion
    if (orig_activateCode) {
        ((void (*)(id, SEL, NSString *, void (^)(BOOL, NSString *, id)))orig_activateCode)
            (self, _cmd, code, safeCompletion);
    } else {
        // 如果原始 IMP 找不到，直接调 completion
        safeCompletion(YES, @"2035-12-31", nil);
    }
}

// activationStampPath — 返回本地路径
static NSString *hook_stampPath(id self, SEL _cmd) {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [doc stringByAppendingPathComponent:@"www_activation_stamp.plist"];
}

// checkTask — 跳过
static void hook_checkTask(id self, SEL _cmd) {
    NSLog(@"[KFun] checkTask -> skipped");
}

// verifyWithCompletion: — 调用原始方法，替换 completion
static void hook_verifyCompletion(id self, SEL _cmd, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[KFun] verifyWithCompletion -> wrapping completion");
    writeStamp();

    void (^safeCompletion)(BOOL, NSString *, id) = ^(BOOL success, NSString *expire, id error) {
        NSLog(@"[KFun] verify completion -> forced YES");
        writeStamp();
        if (completion) {
            NSDateFormatter *f = [[NSDateFormatter alloc] init];
            [f setDateFormat:@"yyyy-MM-dd"];
            completion(YES, [f stringFromDate:
                [NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10]], nil);
        }
    };

    if (orig_verifyCompletion) {
        ((void (*)(id, SEL, void (^)(BOOL, NSString *, id)))orig_verifyCompletion)
            (self, _cmd, safeCompletion);
    } else {
        safeCompletion(YES, @"2035-12-31", nil);
    }
}

// ============================================================
#pragma mark - Safe swizzle helper
// ============================================================

static BOOL swizzle(Class cls, SEL sel, IMP newImp, IMP *origOut, const char *types) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[KFun] WARN: -[%@ %@] not found", cls, NSStringFromSelector(sel));
        return NO;
    }
    if (origOut) *origOut = method_getImplementation(m);
    if (types) class_addMethod(cls, sel, newImp, types);
    method_setImplementation(m, newImp);
    NSLog(@"[KFun] OK: -[%@ %@] swizzled", cls, NSStringFromSelector(sel));
    return YES;
}

// ============================================================
#pragma mark - Constructor
// ============================================================

__attribute__((constructor))
static void KFunAutopsy_init(void) {
    NSLog(@"[KFun] ========== dylib loaded ==========");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{

        // ---- Hook WWWActivationViewController ----
        Class vcCls = objc_getClass("WWWActivationViewController");
        if (vcCls) {
            NSLog(@"[KFun] Found WWWActivationViewController");

            swizzle(vcCls, @selector(viewDidLoad),
                    (IMP)hook_viewDidLoad, &orig_viewDidLoad, "v@:");

            swizzle(vcCls, @selector(viewDidAppear:),
                    (IMP)hook_viewDidAppear, &orig_viewDidAppear, "v@:B");

            swizzle(vcCls, NSSelectorFromString(@"onTapVerify"),
                    (IMP)hook_onTapVerify, &orig_onTapVerify, "v@:");
        }

        // ---- Hook WWWActivation ----
        Class actCls = objc_getClass("WWWActivation");
        if (actCls) {
            NSLog(@"[KFun] Found WWWActivation");

            swizzle(actCls, NSSelectorFromString(@"activateCode:completion:"),
                    (IMP)hook_activateCode, &orig_activateCode, "v@:@@?");

            swizzle(actCls, NSSelectorFromString(@"activationStampPath"),
                    (IMP)hook_stampPath, &orig_stampPath, "@@:");

            swizzle(actCls, NSSelectorFromString(@"checkTask"),
                    (IMP)hook_checkTask, &orig_checkTask, "v@:");

            swizzle(actCls, NSSelectorFromString(@"verifyWithCompletion:"),
                    (IMP)hook_verifyCompletion, &orig_verifyCompletion, "v@:@?");
        }

        writeStamp();
        NSLog(@"[KFun] ========== hooks installed ==========");
    });
}
