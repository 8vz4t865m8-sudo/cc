//
//  iphook.m - KFun 卡密验证 Bypass
//  目标: WWWActivationViewController
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

// ============================================================
// 工具函数
// ============================================================
static void hookMethod(const char *className, SEL sel, IMP newImp, IMP *oldImp) {
    Class cls = objc_getClass(className);
    if (!cls) { LOG(@"找不到类: %s", className); return; }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { LOG(@"找不到方法: %s", sel_getName(sel)); return; }
    if (oldImp) *oldImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
    LOG(@"Hooked: %s -> %s", className, sel_getName(sel));
}

// ============================================================
// 伪造响应
// ============================================================
static NSDictionary *fakeAuthData() {
    return @{
        @"code": @0,
        @"msg": @"success",
        @"data": @{
            @"expire": @"2099-12-31 23:59:59",
            @"type": @"lifetime",
            @"uid": @"bypassed"
        }
    };
}

// ============================================================
// 隐藏遮罩
// ============================================================
static void hideAuthMask(id self) {
    id mask = nil;
    @try { mask = [self valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
    if (!mask) @try { mask = [self valueForKey:@"_authMaskView"]; } @catch (NSException *e) {}
    
    if (mask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [mask setValue:@YES forKey:@"hidden"];
            [(UIView *)mask setUserInteractionEnabled:NO];
            [(UIView *)mask removeFromSuperview];
            LOG(@"已移除遮罩");
        });
    }
}

// ============================================================
// 进入主界面
// ============================================================
static void enterMain() {
    id vc = nil;
    @try {
        UIWindowScene *scene = nil;
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = s; break; }
        }
        UIWindow *window = scene ? scene.keyWindow : [UIApplication sharedApplication].keyWindow;
        vc = window.rootViewController;
        while (vc && [vc respondsToSelector:@selector(presentedViewController)] && [vc presentedViewController])
            vc = [vc presentedViewController];
    } @catch (NSException *e) { return; }
    
    if (!vc) return;
    
    // 尝试各种入口
    if ([vc respondsToSelector:@selector(enterMainConsole)]) {
        ((void(*)(id, SEL))objc_msgSend)(vc, @selector(enterMainConsole));
        return;
    }
    if ([vc respondsToSelector:@selector(setupAfterActivation)]) {
        ((void(*)(id, SEL))objc_msgSend)(vc, @selector(setupAfterActivation));
        return;
    }
    
    // 遍历子控制器
    for (id child in [vc valueForKey:@"childViewControllers"]) {
        if ([child respondsToSelector:@selector(enterMainConsole)]) {
            ((void(*)(id, SEL))objc_msgSend)(child, @selector(enterMainConsole));
            return;
        }
        if ([child respondsToSelector:@selector(setupAfterActivation)]) {
            ((void(*)(id, SEL))objc_msgSend)(child, @selector(setupAfterActivation));
            return;
        }
    }
}

// ============================================================
// Hook 实现
// ============================================================

static void hook_activateCode(id self, SEL _cmd, NSString *code, void (^completion)(BOOL, id)) {
    LOG(@"Bypass activateCode: %@", code);
    
    if (completion) {
        completion(YES, fakeAuthData());
    }
    
    // 触发成功 UI
    if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
        ((void(*)(id, SEL, NSString *))objc_msgSend)(self, @selector(buildSuccessViewWithExpire:), @"2099-12-31 23:59:59");
    }
    if ([self respondsToSelector:@selector(showSuccess:completion:)]) {
        ((void(*)(id, SEL, NSString *, void(^)(void)))objc_msgSend)(self, @selector(showSuccess:completion:), @"验证成功", nil);
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        hideAuthMask(self);
        enterMain();
    });
}

static void hook_verifyWithCompletion(id self, SEL _cmd, void (^completion)(BOOL)) {
    LOG(@"Bypass verifyWithCompletion");
    if (completion) completion(YES);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        hideAuthMask(self);
        enterMain();
    });
}

static void hook_checkTask(id self, SEL _cmd) {
    // 空实现，过期检查永远通过
}

static void hook_onTapVerify(id self, SEL _cmd) {
    LOG(@"Bypass onTapVerify");
    if ([self respondsToSelector:@selector(activateCode:completion:)]) {
        ((void(*)(id, SEL, NSString *, void (^)(BOOL, id)))objc_msgSend)(
            self, @selector(activateCode:completion:), @"BYPASSED", ^(BOOL s, id d){});
    }
}

static void hook_shakeField(id self, SEL _cmd) {
    // 禁用错误抖动
}

static void hook_showError(id self, SEL _cmd, NSString *msg) {
    // 拦截错误提示，显示成功
    LOG(@"拦截错误: %@", msg);
    if ([self respondsToSelector:@selector(showSuccess:completion:)]) {
        ((void(*)(id, SEL, NSString *, void(^)(void)))objc_msgSend)(self, @selector(showSuccess:completion:), @"验证成功", nil);
    }
}

// ============================================================
// 网络请求拦截 (兜底)
// ============================================================
static IMP orig_dtwr = NULL;

typedef NSURLSessionDataTask *(*dtwr_t)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));

static NSURLSessionDataTask *hook_dtwr(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    NSString *url = request.URL.absoluteString.lowercaseString;
    NSString *body = nil;
    if (request.HTTPBody) body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
    
    NSArray *kw = @[@"auth", @"verify", @"license", @"activate", @"check", @"login", @"key", @"code", @"card"];
    BOOL isAuth = NO;
    for (NSString *k in kw) {
        if ([url containsString:k] || [body.lowercaseString containsString:k]) { isAuth = YES; break; }
    }
    
    if (isAuth) {
        LOG(@"拦截网络验证: %@", request.URL.absoluteString);
        if (completion) {
            NSString *json = @"{\"code\":0,\"msg\":\"success\",\"data\":{\"expire\":\"2099-12-31 23:59:59\",\"type\":\"lifetime\"}}";
            NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
            NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data, resp, nil); });
        }
        NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        return [s dataTaskWithURL:[NSURL URLWithString:@"http://localhost"]];
    }
    
    return ((dtwr_t)orig_dtwr)(self, _cmd, request, completion);
}

// ============================================================
// 初始化 (延迟执行，避免启动崩溃)
// ============================================================
static void doInit() {
    LOG(@"开始 Hook...");
    
    // 1. Hook WWWActivationViewController 验证方法
    hookMethod("WWWActivationViewController", @selector(activateCode:completion:),
               (IMP)hook_activateCode, NULL);
    hookMethod("WWWActivationViewController", @selector(verifyWithCompletion:),
               (IMP)hook_verifyWithCompletion, NULL);
    hookMethod("WWWActivationViewController", @selector(checkTask),
               (IMP)hook_checkTask, NULL);
    hookMethod("WWWActivationViewController", @selector(onTapVerify),
               (IMP)hook_onTapVerify, NULL);
    hookMethod("WWWActivationViewController", @selector(shakeField),
               (IMP)hook_shakeField, NULL);
    hookMethod("WWWActivationViewController", @selector(showError:),
               (IMP)hook_showError, NULL);
    
    // 2. Hook NSURLSession 作为兜底
    Class sessionCls = objc_getClass("NSURLSession");
    if (sessionCls) {
        Method m = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:completionHandler:));
        if (m) {
            orig_dtwr = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_dtwr);
            LOG(@"Hooked NSURLSession");
        }
    }
    
    LOG(@"初始化完成");
}

__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun Bypass 已加载");
    LOG(@"========================================");
    
    // 【关键修复】延迟初始化，等 UIKit 准备好
    // 方式1: 监听应用启动通知
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification *note) {
        LOG(@"App 启动完成，开始 Hook...");
        doInit();
    }];
    
    // 方式2: 如果 App 已经启动过了，直接执行
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        doInit();
    });
}
