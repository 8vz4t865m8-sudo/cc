
// KFunBypass.m - 不需要服务器的激活绕过
// 参考 cap1JcodeAI.dylib 的做法，直接伪造成功响应

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================
#pragma mark - 工具函数
// ============================================================

static NSString *fakeExpire(void) {
    // 返回10年后的日期字符串，格式和服务器返回的一致
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    return [f stringFromDate:[NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10]];
}

static void writeStamp(void) {
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                      stringByAppendingPathComponent:@"www_activation_stamp.plist"];
    [@{
        @"activated": @YES,
        @"expire": [NSDate dateWithTimeIntervalSinceNow:365.25 * 24 * 3600 * 10],
        @"code": @"BYPASS-OK",
        @"timestamp": [NSDate date],
        @"machine": [[UIDevice currentDevice] identifierForVendor].UUIDString ?: @"unknown",
    } writeToFile:path atomically:YES];
}

// ============================================================
#pragma mark - 保存原始 IMP
// ============================================================

static IMP orig_activateCode = NULL;

// ============================================================
#pragma mark - Hook: activateCode:completion:
// ============================================================
//
// 原始签名: -[WWWActivation activateCode:(NSString*)code completion:(void(^)(long, NSString*, long))completion]
// block 签名: v32@?0q8@16q24
//   q8  = long status   (0=成功, 非0=失败)
//   @16 = NSString* expire (过期时间)
//   q24 = long data     (服务器数据，可能是字典指针或0)
//
// 策略: 不调原始方法，直接构造成功响应调 completion
//

static void hook_activateCode(id self, SEL _cmd, NSString *code, void (^completion)(long, NSString *, long)) {
    NSLog(@"[KFunBypass] activateCode:\"%@\" -> forced success", code);
    writeStamp();

    if (completion) {
        // status=0 表示成功
        // expire = 过期时间字符串
        // data = 0 (原始 dylib 里也是 long，传0就行)
        completion(0, fakeExpire(), 0);
    }
}

// ============================================================
#pragma mark - Swizzle 工具
// ============================================================

static BOOL swizzle(Class cls, SEL sel, IMP newImp, IMP *origOut, const char *types) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[KFunBypass] WARN: -[%@ %@] not found", cls, NSStringFromSelector(sel));
        return NO;
    }
    if (origOut) *origOut = method_getImplementation(m);
    if (types) class_addMethod(cls, sel, newImp, types);
    method_setImplementation(m, newImp);
    NSLog(@"[KFunBypass] OK: -[%@ %@]", cls, NSStringFromSelector(sel));
    return YES;
}

// ============================================================
#pragma mark - Constructor
// ============================================================

__attribute__((constructor))
static void KFunBypass_init(void) {
    NSLog(@"[KFunBypass] ========== loaded ==========");

    // 写激活标记
    writeStamp();

    // 延迟0.5秒等类加载完
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
    dispatch_get_main_queue(), ^{

        Class actCls = objc_getClass("WWWActivation");
        if (actCls) {
            // 只 hook 一个方法：activateCode:completion:
            // 不调原始方法，直接回调 completion(0, expire, 0)
            swizzle(actCls,
                    NSSelectorFromString(@"activateCode:completion:"),
                    (IMP)hook_activateCode,
                    &orig_activateCode,
                    "v@:@@?");
        } else {
            NSLog(@"[KFunBypass] ERROR: WWWActivation class not found!");
        }

        NSLog(@"[KFunBypass] ========== hooks done ==========");
    });
}
