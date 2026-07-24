//
//  iphook.m - KFun 卡密验证 Bypass
//  只 Hook 验证系统，不碰任何推流/网络功能
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

static UIViewController *getTopVC() {
    UIWindowScene *scene = nil;
    for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = s; break; }
    }
    UIWindow *window = scene ? scene.keyWindow : [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = window.rootViewController;
    if (!vc) return nil;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:[UINavigationController class]])
        vc = [(UINavigationController *)vc topViewController];
    return vc;
}

static void enterMain() {
    UIViewController *vc = getTopVC();
    if (!vc) return;
    // 尝试各种可能的主界面入口
    if ([vc respondsToSelector:@selector(enterMainConsole)]) {
        ((void(*)(id, SEL))objc_msgSend)(vc, @selector(enterMainConsole));
        return;
    }
    if ([vc respondsToSelector:@selector(setupAfterActivation)]) {
        ((void(*)(id, SEL))objc_msgSend)(vc, @selector(setupAfterActivation));
        return;
    }
    // 遍历子控制器
    for (UIViewController *child in vc.childViewControllers) {
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

static void hideMask(id self) {
    // 通过 KVC 获取 authMaskView
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
// Hook 实现
// ============================================================

// 1. Hook activateCode:completion: - 核心验证入口
static void hook_activateCode(id self, SEL _cmd, NSString *code, void (^completion)(BOOL, id)) {
    LOG(@"Bypass activateCode: %@", code);

    // 直接回调成功
    if (completion) {
        completion(YES, fakeAuthData());
    }

    // 触发成功 UI
    if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
        ((void(*)(id, SEL, NSString *))objc_msgSend)(self, @selector(buildSuccessViewWithExpire:), @"2099-12-31 23:59:59");
    }

    // 进入主界面
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        hideMask(self);
        enterMain();
    });
}

// 2. Hook verifyWithCompletion:
static void hook_verifyWithCompletion(id self, SEL _cmd, void (^completion)(BOOL)) {
    LOG(@"Bypass verifyWithCompletion");
    if (completion) completion(YES);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        hideMask(self);
        enterMain();
    });
}

// 3. Hook checkTask - 过期检查
static void hook_checkTask(id self, SEL _cmd) {
    // 空实现，永远通过
}

// 4. Hook onTapVerify - 按钮点击
static void hook_onTapVerify(id self, SEL _cmd) {
    LOG(@"Bypass onTapVerify");
    if ([self respondsToSelector:@selector(activateCode:completion:)]) {
        ((void(*)(id, SEL, NSString *, void (^)(BOOL, id)))objc_msgSend)(
            self, @selector(activateCode:completion:), @"BYPASSED", ^(BOOL s, id d){});
    }
}

// 5. Hook shakeField - 禁用错误动画
static void hook_shakeField(id self, SEL _cmd) {
    // 空实现
}

// 6. Hook authenticate: (备用)
static void hook_authenticate(id self, SEL _cmd, id param) {
    LOG(@"Bypass authenticate:");
    if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
        ((void(*)(id, SEL, NSString *))objc_msgSend)(self, @selector(buildSuccessViewWithExpire:), @"2099-12-31 23:59:59");
    }
    hideMask(self);
    enterMain();
}

// ============================================================
// 运行时扫描 Hook
// ============================================================
static void scanAndHookAuthClasses() {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;

    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        const char *cname = class_getName(cls);
        NSString *clsName = [NSString stringWithUTF8String:cname];

        // 跳过系统类
        if ([clsName hasPrefix:@"NS"] || [clsName hasPrefix:@"UI"] ||
            [clsName hasPrefix:@"AV"] || [clsName hasPrefix:@"CA"] ||
            [clsName hasPrefix:@"CG"] || [clsName hasPrefix:@"CF"] ||
            [clsName hasPrefix:@"OS_"] || [clsName hasPrefix:@"__"]) {
            continue;
        }

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        BOOL isAuthClass = NO;

        for (unsigned int j = 0; j < methodCount; j++) {
            SEL sel = method_getName(methods[j]);
            NSString *name = NSStringFromSelector(sel);
            if ([name isEqualToString:@"activateCode:completion:"] ||
                [name isEqualToString:@"verifyWithCompletion:"] ||
                [name isEqualToString:@"buildSuccessViewWithExpire:"] ||
                [name isEqualToString:@"setupAfterActivation"] ||
                [name isEqualToString:@"checkTask"] ||
                [name isEqualToString:@"onTapVerify"] ||
                [name isEqualToString:@"shakeField"] ||
                [name isEqualToString:@"authenticate:"]) {
                isAuthClass = YES;
                break;
            }
        }

        if (methods) free(methods);

        if (isAuthClass) {
            LOG(@"发现验证类: %@", clsName);

            Method m;

            m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
            if (m) method_setImplementation(m, (IMP)hook_activateCode);

            m = class_getInstanceMethod(cls, @selector(verifyWithCompletion:));
            if (m) method_setImplementation(m, (IMP)hook_verifyWithCompletion);

            m = class_getInstanceMethod(cls, @selector(checkTask));
            if (m) method_setImplementation(m, (IMP)hook_checkTask);

            m = class_getInstanceMethod(cls, @selector(onTapVerify));
            if (m) method_setImplementation(m, (IMP)hook_onTapVerify);

            m = class_getInstanceMethod(cls, @selector(shakeField));
            if (m) method_setImplementation(m, (IMP)hook_shakeField);

            m = class_getInstanceMethod(cls, @selector(authenticate:));
            if (m) method_setImplementation(m, (IMP)hook_authenticate);
        }
    }

    free(classes);
}

// ============================================================
// 网络请求拦截 (可选，作为兜底)
// ============================================================
static IMP orig_dataTaskWithRequest = NULL;

typedef NSURLSessionDataTask *(*orig_dtwr_t)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));

static NSURLSessionDataTask *hook_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    NSString *urlStr = request.URL.absoluteString;
    NSString *bodyStr = nil;
    if (request.HTTPBody) {
        bodyStr = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
    }

    // 检测验证请求
    NSString *lowUrl = urlStr.lowercaseString;
    NSString *lowBody = bodyStr.lowercaseString;
    NSArray *kw = @[@"auth", @"verify", @"license", @"activate", @"check", @"login", @"key", @"code", @"card"];
    BOOL isAuth = NO;
    for (NSString *k in kw) {
        if ([lowUrl containsString:k] || [lowBody containsString:k]) { isAuth = YES; break; }
    }

    if (isAuth) {
        LOG(@"拦截验证请求: %@", urlStr);
        if (completion) {
            NSString *json = @"{\"code\":0,\"msg\":\"success\",\"data\":{\"expire\":\"2099-12-31 23:59:59\",\"type\":\"lifetime\"}}";
            NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
            NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data, resp, nil); });
        }
        NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        return [s dataTaskWithURL:[NSURL URLWithString:@"http://localhost"]];
    }

    return ((orig_dtwr_t)orig_dataTaskWithRequest)(self, _cmd, request, completion);
}

// ============================================================
// 定时清理遮罩
// ============================================================
static void scheduleMaskCleanup() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) { scheduleMaskCleanup(); return; }

        // 递归查找并移除遮罩
        void (^scan)(UIView *, int) = ^(UIView *view, int depth) {
            if (depth > 15) return;
            for (UIView *sv in [view.subviews copy]) {
                CGRect f = sv.frame;
                CGSize s = [UIScreen mainScreen].bounds.size;
                BOOL full = (f.size.width >= s.width * 0.9 && f.size.height >= s.height * 0.9);

                BOOL hasInput = NO;
                for (UIView *ssv in sv.subviews) {
                    if ([ssv isKindOfClass:[UITextField class]]) { hasInput = YES; break; }
                    if ([ssv isKindOfClass:[UIButton class]]) {
                        NSString *t = [(UIButton *)ssv titleForState:UIControlStateNormal];
                        if ([t containsString:@"验证"] || [t containsString:@"激活"] || [t containsString:@"登录"]) {
                            hasInput = YES; break;
                        }
                    }
                }

                if (full && hasInput) {
                    LOG(@"清理遮罩: %@", sv);
                    sv.hidden = YES;
                    sv.userInteractionEnabled = NO;
                    [sv removeFromSuperview];
                    continue;
                }
                scan(sv, depth + 1);
            }
        };
        scan(keyWindow, 0);

        scheduleMaskCleanup();
    });
}

// ============================================================
// Constructor
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun 卡密 Bypass 已加载");
    LOG(@"========================================");

    // 1. 运行时扫描验证类
    scanAndHookAuthClasses();

    // 2. Hook NSURLSession 作为兜底
    Class sessionCls = objc_getClass("NSURLSession");
    if (sessionCls) {
        Method m = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:completionHandler:));
        if (m) {
            orig_dataTaskWithRequest = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_dataTaskWithRequest);
            LOG(@"Hooked NSURLSession");
        }
    }

    // 3. 启动定时清理
    scheduleMaskCleanup();

    // 4. 监听应用启动
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification *note) {
        LOG(@"App 启动，重新扫描...");
        scanAndHookAuthClasses();
    }];

    LOG(@"初始化完成");
}
