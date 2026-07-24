//
//  iphook.m
//  KFun Card Key Bypass - Pure Dylib
//  注入方式: DYLD_INSERT_LIBRARIES 或 tweak 加载
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#pragma mark - 日志工具

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

#pragma mark - 伪造响应数据

static NSData *fakeAuthResponse(void) {
    static NSData *data = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *json = @"{\"code\":0,\"msg\":\"success\",\"data\":{\"expire\":\"2099-12-31 23:59:59\",\"type\":\"lifetime\",\"uid\":\"bypassed\",\"token\":\"fake_token_12345\"}}";
        data = [json dataUsingEncoding:NSUTF8StringEncoding];
    });
    return data;
}

static NSHTTPURLResponse *fakeHTTPResponse(NSURL *url) {
    return [[NSHTTPURLResponse alloc] initWithURL:url
                                         statusCode:200
                                        HTTPVersion:@"HTTP/1.1"
                                       headerFields:@{@"Content-Type": @"application/json"}];
}

#pragma mark - 工具函数

static BOOL isAuthURL(NSString *urlStr) {
    if (!urlStr) return NO;
    NSString *low = urlStr.lowercaseString;
    NSArray *keywords = @[@"auth", @"verify", @"license", @"activate", @"check", @"login", 
                           @"key", @"code", @"card", @"token", @"bind", @"machine", @"device"];
    for (NSString *kw in keywords) {
        if ([low containsString:kw]) return YES;
    }
    return NO;
}

static BOOL isAuthBody(NSData *body) {
    if (!body) return NO;
    NSString *str = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if (!str) return NO;
    NSString *low = str.lowercaseString;
    NSArray *keywords = @[@"auth", @"verify", @"license", @"activate", @"code", @"key", 
                           @"card", @"token", @"udid", @"device", @"machine"];
    for (NSString *kw in keywords) {
        if ([low containsString:kw]) return YES;
    }
    return NO;
}

#pragma mark - 递归隐藏遮罩

static void hideAuthMasks(UIView *view, int depth) {
    if (depth > 20) return;

    for (UIView *sv in view.subviews) {
        CGRect frame = sv.frame;
        CGSize screen = [UIScreen mainScreen].bounds.size;

        // 检测全屏遮罩特征
        BOOL isFullScreen = (frame.size.width >= screen.width * 0.9 &&
                             frame.size.height >= screen.height * 0.9);

        if (isFullScreen) {
            // 检查是否包含验证元素
            BOOL hasAuthElements = NO;
            for (UIView *ssv in sv.subviews) {
                if ([ssv isKindOfClass:[UITextField class]]) {
                    hasAuthElements = YES;
                    break;
                }
                if ([ssv isKindOfClass:[UIButton class]]) {
                    UIButton *btn = (UIButton *)ssv;
                    NSString *title = [btn titleForState:UIControlStateNormal];
                    if ([title containsString:@"验证"] || [title containsString:@"激活"] ||
                        [title containsString:@"登录"] || [title containsString:@"确定"]) {
                        hasAuthElements = YES;
                        break;
                    }
                }
            }

            // 半透明黑色背景也是特征
            BOOL isMaskStyle = (sv.alpha < 1.0 || 
                                CGColorEqualToColor(sv.backgroundColor.CGColor, [UIColor blackColor].CGColor) ||
                                sv.backgroundColor == nil);

            if (hasAuthElements || (isMaskStyle && isFullScreen)) {
                LOG(@"Hiding auth mask: %@", sv);
                sv.hidden = YES;
                sv.userInteractionEnabled = NO;
                [sv removeFromSuperview];
                continue;
            }
        }

        hideAuthMasks(sv, depth + 1);
    }
}

#pragma mark - 定时清理任务

static void scheduleMaskCleanup(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
            }
        }
        if (keyWindow) {
            hideAuthMasks(keyWindow, 0);
        }
        // 每 3 秒检查一次
        scheduleMaskCleanup();
    });
}

#pragma mark - NSURLSession Hook

typedef NSURLSessionDataTask *(*orig_dataTaskWithRequest_t)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
static orig_dataTaskWithRequest_t orig_dataTaskWithRequest = NULL;

static NSURLSessionDataTask *hook_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = request.URL;
    NSString *urlStr = url.absoluteString;

    if (isAuthURL(urlStr) || isAuthBody(request.HTTPBody)) {
        LOG(@"Intercepted auth request: %@", urlStr);

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(fakeAuthResponse(), fakeHTTPResponse(url), nil);
            });
        }

        // 返回一个假的 task（从空 session 创建）
        NSURLSession *emptySession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        NSURLSessionDataTask *fakeTask = [emptySession dataTaskWithURL:[NSURL URLWithString:@"http://localhost"]];
        return fakeTask;
    }

    return orig_dataTaskWithRequest(self, _cmd, request, completion);
}

#pragma mark - NSURLConnection Hook (同步请求)

typedef NSData *(*orig_sendSyncRequest_t)(Class, SEL, NSURLRequest *, NSURLResponse **, NSError **);
static orig_sendSyncRequest_t orig_sendSyncRequest = NULL;

static NSData *hook_sendSyncRequest(Class self, SEL _cmd, NSURLRequest *request, NSURLResponse **response, NSError **error) {
    if (isAuthURL(request.URL.absoluteString) || isAuthBody(request.HTTPBody)) {
        LOG(@"Intercepted sync auth request: %@", request.URL.absoluteString);
        if (response) *response = fakeHTTPResponse(request.URL);
        if (error) *error = nil;
        return fakeAuthResponse();
    }
    return orig_sendSyncRequest(self, _cmd, request, response, error);
}

#pragma mark - 运行时扫描 Hook 验证类

static void hookAuthClasses(void) {
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
            [clsName hasPrefix:@"CG"] || [clsName hasPrefix:@"CF"]) {
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
                [name isEqualToString:@"onTapVerify"]) {
                isAuthClass = YES;
                break;
            }
        }

        if (methods) free(methods);

        if (isAuthClass) {
            LOG(@"Found auth class: %@", clsName);

            // Hook activateCode:completion:
            Method m1 = class_getInstanceMethod(cls, @selector(activateCode:completion:));
            if (m1) {
                IMP newImp = imp_implementationWithBlock(^(id self, NSString *code, void (^completion)(BOOL, id)) {
                    LOG(@"Bypassed activateCode: %@", code);
                    if (completion) {
                        NSDictionary *fakeData = @{
                            @"code": @0,
                            @"msg": @"success",
                            @"data": @{
                                @"expire": @"2099-12-31 23:59:59",
                                @"type": @"lifetime"
                            }
                        };
                        completion(YES, fakeData);
                    }
                    // 触发成功 UI
                    if ([self respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
                        ((void (*)(id, SEL, NSString *))objc_msgSend)(self, @selector(buildSuccessViewWithExpire:), @"2099-12-31 23:59:59");
                    }
                    if ([self respondsToSelector:@selector(setupAfterActivation)]) {
                        ((void (*)(id, SEL))objc_msgSend)(self, @selector(setupAfterActivation));
                    }
                    // 隐藏遮罩
                    id mask = [self valueForKey:@"authMaskView"];
                    if (mask) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [mask setValue:@YES forKey:@"hidden"];
                            [(UIView *)mask removeFromSuperview];
                        });
                    }
                });
                method_setImplementation(m1, newImp);
            }

            // Hook verifyWithCompletion:
            Method m2 = class_getInstanceMethod(cls, @selector(verifyWithCompletion:));
            if (m2) {
                IMP newImp = imp_implementationWithBlock(^(id self, void (^completion)(BOOL)) {
                    LOG(@"Bypassed verifyWithCompletion");
                    if (completion) completion(YES);
                    id mask = [self valueForKey:@"authMaskView"];
                    if (mask) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [mask setValue:@YES forKey:@"hidden"];
                            [(UIView *)mask removeFromSuperview];
                        });
                    }
                });
                method_setImplementation(m2, newImp);
            }

            // Hook checkTask
            Method m3 = class_getInstanceMethod(cls, @selector(checkTask));
            if (m3) {
                IMP newImp = imp_implementationWithBlock(^(id self) {
                    // 什么都不做，过期检查永远通过
                });
                method_setImplementation(m3, newImp);
            }

            // Hook onTapVerify
            Method m4 = class_getInstanceMethod(cls, @selector(onTapVerify));
            if (m4) {
                IMP newImp = imp_implementationWithBlock(^(id self) {
                    LOG(@"Bypassed onTapVerify");
                    if ([self respondsToSelector:@selector(activateCode:completion:)]) {
                        ((void (*)(id, SEL, NSString *, void (^)(BOOL, id)))objc_msgSend)(
                            self, @selector(activateCode:completion:), @"BYPASSED", ^(BOOL s, id d){});
                    }
                });
                method_setImplementation(m4, newImp);
            }

            // Hook shakeField (禁用错误动画)
            Method m5 = class_getInstanceMethod(cls, @selector(shakeField));
            if (m5) {
                IMP newImp = imp_implementationWithBlock(^(id self) {
                    // 空实现
                });
                method_setImplementation(m5, newImp);
            }
        }
    }

    free(classes);
}

#pragma mark - Constructor

__attribute__((constructor))
static void iphook_init(void) {
    LOG(@"IPH loaded into process: %@", [[NSProcessInfo processInfo] processName]);

    // 1. Hook NSURLSession
    Class sessionCls = objc_getClass("NSURLSession");
    if (sessionCls) {
        Method m = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:completionHandler:));
        if (m) {
            orig_dataTaskWithRequest = (orig_dataTaskWithRequest_t)method_setImplementation(m, (IMP)hook_dataTaskWithRequest);
            LOG(@"Hooked NSURLSession::dataTaskWithRequest:");
        }
    }

    // 2. Hook NSURLConnection (同步)
    Class connCls = objc_getClass("NSURLConnection");
    if (connCls) {
        Method m = class_getClassMethod(connCls, @selector(sendSynchronousRequest:returningResponse:error:));
        if (m) {
            orig_sendSyncRequest = (orig_sendSyncRequest_t)method_setImplementation(m, (IMP)hook_sendSyncRequest);
            LOG(@"Hooked NSURLConnection::sendSynchronousRequest:");
        }
    }

    // 3. 扫描并 Hook 验证类
    hookAuthClasses();

    // 4. 启动定时清理遮罩
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scheduleMaskCleanup();
    });

    // 5. 监听应用启动，重新扫描
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification *note) {
        LOG(@"App launched, rescanning auth classes...");
        hookAuthClasses();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *window in scene.windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                }
            }
            if (keyWindow) hideAuthMasks(keyWindow, 0);
        });
    }];

    LOG(@"IPH init complete");
}
