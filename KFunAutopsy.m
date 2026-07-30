// KFunAutopsy.m - kfun activation bypass
//
// 分析结论:
// 1. 主 app 的 activateCode:completion: 是混淆代码，不能调用
// 2. 原始 dylib 完全替换了这个方法
// 3. 原始 dylib 调用 completion block 触发 onVerify 回调
// 4. 主 app 通过 activationStampPath 的 plist 判断激活状态
// 5. onVerify block 被调用后，主界面才加载内容
//
// 策略:
// - hook activateCode:completion: → 不调原始，直接回调 completion(YES)
// - hook activationStampPath → 返回本地 plist 路径
// - hook checkTask → 跳过
// - hook verifyWithCompletion: → 直接回调成功
// - hook onTapVerify → 直接调 onVerify block + dismiss
// - hook showSuccess:completion: → 直接调 completion
// - 写入正确的激活 plist

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================
#pragma mark - 激活 plist
// ============================================================

static NSString *stampPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@"www_activation_stamp.plist"];
}

static void writeStamp(void) {
    // 写入和正版格式一致的激活 plist
    [@{
        @"activated": @YES,
        @"expire": [NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10],
        @"code": @"BYPASS-OK",
        @"timestamp": [NSDate date],
        @"machine": [[UIDevice currentDevice] identifierForVendor].UUIDString ?: @"unknown",
    } writeToFile:stampPath() atomically:YES];
    NSLog(@"[KFun] stamp -> %@", stampPath());
}

static NSString *fakeExpire(void) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f setDateFormat:@"yyyy-MM-dd"];
    return [f stringFromDate:[NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10]];
}

// ============================================================
#pragma mark - 保存原始 IMP
// ============================================================

static IMP orig_activateCode = NULL;
static IMP orig_stampPath = NULL;
static IMP orig_checkTask = NULL;
static IMP orig_verifyCompletion = NULL;
static IMP orig_onTapVerify = NULL;
static IMP orig_viewDidLoad = NULL;
static IMP orig_viewDidAppear = NULL;
static IMP orig_showSuccess = NULL;

// ============================================================
#pragma mark - WWWActivation hooks
// ============================================================

// activateCode:completion: — 完全替换，不调原始方法
// 原始方法是混淆代码，调了会崩
static void hook_activateCode(id self, SEL _cmd, NSString *code, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[KFun] activateCode:\"%@\" -> forced success", code);
    writeStamp();

    // 直接调用 completion block，返回成功
    if (completion) {
        completion(YES, fakeExpire(), nil);
    }
}

// activationStampPath — 返回本地路径
static NSString *hook_stampPath(id self, SEL _cmd) {
    return stampPath();
}

// checkTask — 跳过定时验证
static void hook_checkTask(id self, SEL _cmd) {
    NSLog(@"[KFun] checkTask -> skipped");
}

// verifyWithCompletion: — 直接返回成功
static void hook_verifyCompletion(id self, SEL _cmd, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[KFun] verifyWithCompletion -> forced success");
    writeStamp();
    if (completion) {
        completion(YES, fakeExpire(), nil);
    }
}

// ============================================================
#pragma mark - WWWActivationViewController hooks
// ============================================================

// onTapVerify — 不调原始（混淆），直接调 onVerify block
static void hook_onTapVerify(id self, SEL _cmd) {
    NSLog(@"[KFun] onTapVerify -> call onVerify + dismiss");
    writeStamp();

    // 调用 onVerify block（主界面靠这个加载内容）
    @try {
        void (^onVerify)(void) = [self valueForKey:@"onVerify"];
        if (onVerify) {
            NSLog(@"[KFun] calling onVerify block");
            onVerify();
        } else {
            NSLog(@"[KFun] onVerify is nil");
        }
    } @catch (NSException *e) {
        NSLog(@"[KFun] onVerify error: %@", e);
    }

    // 延迟 dismiss
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

// viewDidLoad — 写标记
static void hook_viewDidLoad(id self, SEL _cmd) {
    writeStamp();
    if (orig_viewDidLoad) {
        ((void (*)(id, SEL))orig_viewDidLoad)(self, _cmd);
    }
}

// viewDidAppear — 兜底 dismiss
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) {
        ((void (*)(id, SEL, BOOL))orig_viewDidAppear)(self, _cmd, animated);
    }
    // 2秒后如果还在激活界面就自动消失
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        writeStamp();
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

// showSuccess:completion: — 直接调 completion
static void hook_showSuccess(id self, SEL _cmd, BOOL success, void (^completion)(void)) {
    NSLog(@"[KFun] showSuccess -> forced YES");
    writeStamp();
    if (completion) completion();
}

// ============================================================
#pragma mark - Swizzle
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
    NSLog(@"[KFun] OK: -[%@ %@]", cls, NSStringFromSelector(sel));
    return YES;
}

// ============================================================
#pragma mark - Constructor
// ============================================================

__attribute__((constructor))
static void KFunAutopsy_init(void) {
    NSLog(@"[KFun] ========== dylib loaded ==========");

    // 立即写入激活标记
    writeStamp();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{

        // ---- Hook WWWActivation ----
        Class actCls = objc_getClass("WWWActivation");
        if (actCls) {
            NSLog(@"[KFun] Found WWWActivation");

            // activateCode:completion: — 完全替换，不调原始
            swizzle(actCls, NSSelectorFromString(@"activateCode:completion:"),
                    (IMP)hook_activateCode, &orig_activateCode, "v@:@@?");

            swizzle(actCls, NSSelectorFromString(@"activationStampPath"),
                    (IMP)hook_stampPath, &orig_stampPath, "@@:");

            swizzle(actCls, NSSelectorFromString(@"checkTask"),
                    (IMP)hook_checkTask, &orig_checkTask, "v@:");

            swizzle(actCls, NSSelectorFromString(@"verifyWithCompletion:"),
                    (IMP)hook_verifyCompletion, &orig_verifyCompletion, "v@:@?");
        }

        // ---- Hook WWWActivationViewController ----
        Class vcCls = objc_getClass("WWWActivationViewController");
        if (vcCls) {
            NSLog(@"[KFun] Found WWWActivationViewController");

            swizzle(vcCls, NSSelectorFromString(@"onTapVerify"),
                    (IMP)hook_onTapVerify, &orig_onTapVerify, "v@:");

            swizzle(vcCls, NSSelectorFromString(@"showSuccess:completion:"),
                    (IMP)hook_showSuccess, &orig_showSuccess, "v@:B@?");

            swizzle(vcCls, @selector(viewDidLoad),
                    (IMP)hook_viewDidLoad, &orig_viewDidLoad, "v@:");

            swizzle(vcCls, @selector(viewDidAppear:),
                    (IMP)hook_viewDidAppear, &orig_viewDidAppear, "v@:B");
        }

        writeStamp();
        NSLog(@"[KFun] ========== hooks installed ==========");
    });
}
