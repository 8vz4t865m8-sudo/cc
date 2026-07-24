//
//  iphook.m - 测试版
//  只 Hook showError: 和加弹窗测试
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

// 弹窗测试
static void showTestAlert() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"[IPH] 测试"
                                                                       message:@"dylib已加载"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = scene.keyWindow;
                break;
            }
        }
        if (!window) window = [UIApplication sharedApplication].keyWindow;
        if (window && window.rootViewController) {
            [window.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

// Hook showError:
static void hook_showError(id self, SEL _cmd, NSString *msg) {
    LOG(@"[TEST] showError被调用: %@", msg);
    // 不显示错误，改为弹窗提示
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"[IPH] 拦截"
                                                                       message:[NSString stringWithFormat:@"原错误: %@", msg]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = scene.keyWindow;
                break;
            }
        }
        if (!window) window = [UIApplication sharedApplication].keyWindow;
        if (window && window.rootViewController) {
            [window.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

static void doInit() {
    LOG(@"开始 Hook...");
    
    Class cls = objc_getClass("WWWActivationViewController");
    if (!cls) {
        LOG(@"找不到 WWWActivationViewController!");
        return;
    }
    LOG(@"找到类: WWWActivationViewController");
    
    Method m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        method_setImplementation(m, (IMP)hook_showError);
        LOG(@"Hooked showError:");
    } else {
        LOG(@"找不到 showError:");
    }
    
    LOG(@"初始化完成");
}

__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun Bypass 测试版 已加载");
    LOG(@"========================================");
    
    // 弹窗测试
    showTestAlert();
    
    // 延迟 Hook
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        doInit();
    });
}
