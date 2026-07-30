// KFunAutopsy.m - kfun activation bypass
// 核心思路: hook activateCode:completion: 和 verifyWithCompletion:
// 让 completion block 总是返回成功，触发主界面加载

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================================
#pragma mark - Helpers
// ============================================================

static NSString *fakeExpire(void) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f setDateFormat:@"yyyy-MM-dd"];
    return [f stringFromDate:[NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10]];
}

static void writeStamp(void) {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [doc stringByAppendingPathComponent:@"www_activation_stamp.plist"];
    [@{
        @"activated": @YES,
        @"expire": [NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10],
        @"code": @"BYPASS",
        @"timestamp": [NSDate date],
    } writeToFile:path atomically:YES];
}

// ============================================================
#pragma mark - Saved IMPs
// ============================================================

static IMP orig_activateCode = NULL;
static IMP orig_verifyCompletion = NULL;
static IMP orig_stampPath = NULL;
static IMP orig_checkTask = NULL;
static IMP orig_onTapVerify = NULL;
static IMP orig_viewDidLoad = NULL;
static IMP orig_viewDidAppear = NULL;

// ============================================================
#pragma mark - WWWActivation hooks
// ============================================================

// activateCode:completion:
// 关键: 调用原始方法，但替换 completion block
// completion block 必须被调用才能触发主界面加载
static void hook_activateCode(id self, SEL _cmd, NSString *code, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[KFun] activateCode:\"%@\"", code);
    writeStamp();

    // 包装 completion: 无论原始结果如何，都返回成功
    void (^safeCompletion)(BOOL, NSString *, id) = ^(BOOL success, NSString *expire, id error) {
        NSLog(@"[KFun] activateCode completion -> forced YES (original was %d)", success);
        writeStamp();
        if (completion) {
            completion(YES, fakeExpire(), nil);
        }
    };

    // 调用原始方法（混淆代码），但用包装后的 completion
    if (orig_activateCode) {
        ((void (*)(id, SEL, NSString *, void (^)(BOOL, NSString *, id)))orig_activateCode)
            (self, _cmd, code, safeCompletion);
    } else {
        safeCompletion(YES, nil, nil);
    }
}

// verifyWithCompletion:
static void hook_verifyCompletion(id self, SEL _cmd, void (^completion)(BOOL, NSString *, id)) {
    NSLog(@"[KFun] verifyWithCompletion");
    writeStamp();

    void (^safeCompletion)(BOOL, NSString *, id) = ^(BOOL success, NSString *expire, id error) {
        NSLog(@"[KFun] verify completion -> forced YES");
        writeStamp();
        if (completion) {
            completion(YES, fakeExpire(), nil);
        }
    };

    if (orig_verifyCompletion) {
        ((void (*)(id, SEL, void (^)(BOOL, NSString *, id)))orig_verifyCompletion)
            (self, _cmd, safeCompletion);
    } else {
        safeCompletion(YES, nil, nil);
    }
}

// activationStampPath
static NSString *hook_stampPath(id self, SEL _cmd) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@"www_activation_stamp.plist"];
}

// checkTask -> skip
static void hook_checkTask(id self, SEL _cmd) {
    NSLog(@"[KFun] checkTask -> skipped");
}

// ============================================================
#pragma mark - WWWActivationViewController hooks
// ============================================================

// onTapVerify — 调用 activateCode:completion: 触发完整验证流程
// 不调用原始 onTapVerify（混淆代码会崩），而是手动调 activateCode:completion:
static void hook_onTapVerify(id self, SEL _cmd) {
    NSLog(@"[KFun] onTapVerify -> manual activateCode flow");
    writeStamp();

    // 从 codeField 读取用户输入的卡密
    NSString *code = @"BYPASS";
    @try {
        id field = [self valueForKey:@"codeField"];
        if ([field respondsToSelector:@selector(text)]) {
            NSString *t = [field performSelector:@selector(text)];
            if (t.length > 0) code = t;
        }
    } @catch (NSException *e) {}

    // 找到 WWWActivation 实例并调用 activateCode:completion:
    // WWWActivation 是单例，通过 shared 获取
    Class actCls = objc_getClass("WWWActivation");
    if (actCls) {
        SEL sharedSel = NSSelectorFromString(@"shared");
        if ([actCls respondsToSelector:sharedSel]) {
            id actInstance = ((id (*)(id, SEL))objc_msgSend)((id)actCls, sharedSel);
            if (actInstance) {
                // 获取 onVerify block
                void (^onVerify)(void) = nil;
                @try {
                    onVerify = [self valueForKey:@"onVerify"];
                } @catch (NSException *e) {}

                // 调用 activateCode:completion:
                SEL activateSel = NSSelectorFromString(@"activateCode:completion:");
                if ([actInstance respondsToSelector:activateSel]) {
                    void (^wrappedCompletion)(BOOL, NSString *, id) = ^(BOOL s, NSString *exp, id err) {
                        NSLog(@"[KFun] activateCode completed, calling onVerify");
                        writeStamp();
                        if (onVerify) onVerify();
                    };
                    ((void (*)(id, SEL, NSString *, void (^)(BOOL, NSString *, id)))objc_msgSend)
                        (actInstance, activateSel, code, wrappedCompletion);
                    return;
                }
            }
        }
    }

    // 如果上面都失败，直接调 onVerify + dismiss
    @try {
        void (^onVerify)(void) = [self valueForKey:@"onVerify"];
        if (onVerify) onVerify();
    } @catch (NSException *e) {}

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

// viewDidLoad — 写标记 + 调原始
static void hook_viewDidLoad(id self, SEL _cmd) {
    writeStamp();
    if (orig_viewDidLoad) {
        ((void (*)(id, SEL))orig_viewDidLoad)(self, _cmd);
    }
    NSLog(@"[KFun] WWWActivationViewController.viewDidLoad");
}

// viewDidAppear — 延迟 dismiss 兜底
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) {
        ((void (*)(id, SEL, BOOL))orig_viewDidAppear)(self, _cmd, animated);
    }
    NSLog(@"[KFun] WWWActivationViewController.viewDidAppear");
}

// ============================================================
#pragma mark - Swizzle helper
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{

        // ---- Hook WWWActivation ----
        Class actCls = objc_getClass("WWWActivation");
        if (actCls) {
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
            swizzle(vcCls, NSSelectorFromString(@"onTapVerify"),
                    (IMP)hook_onTapVerify, &orig_onTapVerify, "v@:");
            swizzle(vcCls, @selector(viewDidLoad),
                    (IMP)hook_viewDidLoad, &orig_viewDidLoad, "v@:");
            swizzle(vcCls, @selector(viewDidAppear:),
                    (IMP)hook_viewDidAppear, &orig_viewDidAppear, "v@:B");
        }

        writeStamp();
        NSLog(@"[KFun] ========== hooks installed ==========");
    });
}
