//
//  iphook.m - KFun 卡密验证 Bypass
//  目标: WWWActivationViewController
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

static void hideAuthUI(id self) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id mask = nil;
        @try { mask = [self valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
        if (mask) {
            [mask setValue:@YES forKey:@"hidden"];
            [(UIView *)mask setUserInteractionEnabled:NO];
            [(UIView *)mask removeFromSuperview];
        }
        id errorLabel = nil;
        @try { errorLabel = [self valueForKey:@"errorLabel"]; } @catch (NSException *e) {}
        if (errorLabel) {
            [errorLabel setValue:@"" forKey:@"text"];
            [(UIView *)errorLabel setHidden:YES];
        }
        id successView = nil;
        @try { successView = [self valueForKey:@"successView"]; } @catch (NSException *e) {}
        if (successView) {
            [successView setValue:@YES forKey:@"hidden"];
            [(UIView *)successView removeFromSuperview];
        }
    });
}

static void tryEnterMain(id self) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:@selector(setupAfterActivation)]) {
            ((void(*)(id, SEL))objc_msgSend)(self, @selector(setupAfterActivation));
            return;
        }
        UIWindowScene *scene = nil;
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = s; break; }
        }
        UIWindow *window = scene ? scene.keyWindow : [UIApplication sharedApplication].keyWindow;
        id vc = window.rootViewController;
        while (vc && [vc respondsToSelector:@selector(presentedViewController)] && [vc presentedViewController])
            vc = [vc presentedViewController];
        if (vc && [vc respondsToSelector:@selector(setupAfterActivation)]) {
            ((void(*)(id, SEL))objc_msgSend)(vc, @selector(setupAfterActivation));
        }
    });
}

static NSDictionary *fakeSuccessData() {
    return @{
        @"code": @0,
        @"msg": @"success",
        @"data": @{
            @"expire": @"2099-12-31 23:59:59",
            @"type": @"lifetime"
        }
    };
}

static void hook_activateCode(id self, SEL _cmd, NSString *code, void (^completion)(BOOL success, id data)) {
    LOG(@"Bypass activateCode: %@", code);
    if (completion) completion(YES, fakeSuccessData());
    hideAuthUI(self);
    tryEnterMain(self);
}

static void hook_verifyWithCompletion(id self, SEL _cmd, void (^completion)(BOOL success)) {
    LOG(@"Bypass verifyWithCompletion");
    if (completion) completion(YES);
    hideAuthUI(self);
    tryEnterMain(self);
}

static void hook_showError(id self, SEL _cmd, NSString *msg) {
    LOG(@"拦截错误: %@", msg);
    if ([self respondsToSelector:@selector(showSuccess:completion:)]) {
        ((void(*)(id, SEL, NSString *, void (^)(void)))objc_msgSend)(
            self, @selector(showSuccess:completion:), @"验证成功", ^{});
    }
    hideAuthUI(self);
    tryEnterMain(self);
}

static void hook_checkTask(id self, SEL _cmd) {}

static void hook_shakeField(id self, SEL _cmd) {}

static void hook_onTapVerify(id self, SEL _cmd) {
    LOG(@"Bypass onTapVerify");
    if ([self respondsToSelector:@selector(activateCode:completion:)]) {
        ((void(*)(id, SEL, NSString *, void (^)(BOOL, id)))objc_msgSend)(
            self, @selector(activateCode:completion:), @"BYPASSED", ^(BOOL success, id data) {});
    }
}

static void hook_prefillCode(id self, SEL _cmd, NSString *code) {
    LOG(@"拦截预填充: %@", code);
    if ([self respondsToSelector:@selector(activateCode:completion:)]) {
        ((void(*)(id, SEL, NSString *, void (^)(BOOL, id)))objc_msgSend)(
            self, @selector(activateCode:completion:), @"BYPASSED", ^(BOOL success, id data) {});
    }
}

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
        LOG(@"拦截验证请求: %@", request.URL.absoluteString);
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

static void doInit() {
    LOG(@"开始 Hook...");
    const char *clsName = "WWWActivationViewController";
    Class cls = objc_getClass(clsName);
    if (!cls) { LOG(@"找不到类!"); return; }
    
    Method m;
    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) { method_setImplementation(m, (IMP)hook_activateCode); LOG(@"Hooked activateCode:completion:"); }
    
    m = class_getInstanceMethod(cls, @selector(verifyWithCompletion:));
    if (m) { method_setImplementation(m, (IMP)hook_verifyWithCompletion); LOG(@"Hooked verifyWithCompletion:"); }
    
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) { method_setImplementation(m, (IMP)hook_showError); LOG(@"Hooked showError:"); }
    
    m = class_getInstanceMethod(cls, @selector(checkTask));
    if (m) { method_setImplementation(m, (IMP)hook_checkTask); LOG(@"Hooked checkTask"); }
    
    m = class_getInstanceMethod(cls, @selector(shakeField));
    if (m) { method_setImplementation(m, (IMP)hook_shakeField); LOG(@"Hooked shakeField"); }
    
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) { method_setImplementation(m, (IMP)hook_onTapVerify); LOG(@"Hooked onTapVerify"); }
    
    m = class_getInstanceMethod(cls, @selector(prefillCode:));
    if (m) { method_setImplementation(m, (IMP)hook_prefillCode); LOG(@"Hooked prefillCode:"); }
    
    Class sessionCls = objc_getClass("NSURLSession");
    if (sessionCls) {
        m = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:completionHandler:));
        if (m) { orig_dtwr = method_getImplementation(m); method_setImplementation(m, (IMP)hook_dtwr); LOG(@"Hooked NSURLSession"); }
    }
    
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
