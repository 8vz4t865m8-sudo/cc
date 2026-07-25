//
//  iphook.m - KFun 卡密验证 Bypass (网络拦截版)
//  策略: 只 Hook NSURLSession，拦截验证请求返回伪造成功
//  不碰任何 UI 方法，让原 App 自己处理
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

// ============================================================
// 伪造成功响应
// ============================================================
static NSData *fakeSuccessData() {
    static NSData *data = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *json = @"{\"code\":0,\"msg\":\"success\",\"data\":{\"expire\":\"2099-12-31 23:59:59\",\"type\":\"lifetime\",\"uid\":\"bypassed\"}}";
        data = [json dataUsingEncoding:NSUTF8StringEncoding];
    });
    return data;
}

static NSHTTPURLResponse *fakeResponse(NSURL *url) {
    return [[NSHTTPURLResponse alloc] initWithURL:url
                                         statusCode:200
                                        HTTPVersion:@"HTTP/1.1"
                                       headerFields:@{@"Content-Type": @"application/json"}];
}

// ============================================================
// 判断是否是验证请求
// ============================================================
static BOOL isAuthRequest(NSURLRequest *request) {
    NSString *url = request.URL.absoluteString.lowercaseString;
    NSString *body = nil;
    if (request.HTTPBody) {
        body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
    }

    // 检查 URL 是否包含验证关键词
    NSArray *urlKeywords = @[@"auth", @"verify", @"license", @"activate", @"check", @"login", 
                              @"key", @"code", @"card", @"token", @"bind", @"machine", @"device"];
    for (NSString *k in urlKeywords) {
        if ([url containsString:k]) return YES;
    }

    // 检查 POST body 是否包含卡密相关字段
    if (body) {
        NSString *lowBody = body.lowercaseString;
        NSArray *bodyKeywords = @[@"code", @"kami", @"card", @"key", @"auth", @"verify", 
                                  @"license", @"activate", @"token", @"udid", @"device", @"machine"];
        for (NSString *k in bodyKeywords) {
            if ([lowBody containsString:k]) return YES;
        }
    }

    return NO;
}

// ============================================================
// Hook NSURLSession dataTaskWithRequest:completionHandler:
// ============================================================
static IMP orig_dtwr = NULL;

typedef NSURLSessionDataTask *(*dtwr_t)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));

static NSURLSessionDataTask *hook_dtwr(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *)) {

    if (isAuthRequest(request)) {
        LOG(@"拦截验证请求: %@", request.URL.absoluteString);
        if (request.HTTPBody) {
            NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            LOG(@"请求体: %@", body);
        }

        // 直接返回伪造成功响应
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(fakeSuccessData(), fakeResponse(request.URL), nil);
            });
        }

        // 返回一个假的 task
        NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        return [s dataTaskWithURL:[NSURL URLWithString:@"http://localhost"]];
    }

    // 非验证请求，走原逻辑
    return ((dtwr_t)orig_dtwr)(self, _cmd, request, completion);
}

// ============================================================
// Hook NSURLConnection sendSynchronousRequest (备用)
// ============================================================
static IMP orig_sendSync = NULL;

typedef NSData *(*sendSync_t)(Class, SEL, NSURLRequest *, NSURLResponse **, NSError **);

static NSData *hook_sendSync(Class self, SEL _cmd, NSURLRequest *request, NSURLResponse **response, NSError **error) {

    if (isAuthRequest(request)) {
        LOG(@"拦截同步验证请求: %@", request.URL.absoluteString);
        if (response) *response = fakeResponse(request.URL);
        if (error) *error = nil;
        return fakeSuccessData();
    }

    return ((sendSync_t)orig_sendSync)(self, _cmd, request, response, error);
}

// ============================================================
// 初始化
// ============================================================
static void doInit() {
    LOG(@"开始 Hook 网络请求...");

    // Hook NSURLSession
    Class sessionCls = objc_getClass("NSURLSession");
    if (sessionCls) {
        Method m = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:completionHandler:));
        if (m) {
            orig_dtwr = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_dtwr);
            LOG(@"Hooked NSURLSession dataTaskWithRequest:");
        }
    }

    // Hook NSURLConnection (同步请求)
    Class connCls = objc_getClass("NSURLConnection");
    if (connCls) {
        Method m = class_getClassMethod(connCls, @selector(sendSynchronousRequest:returningResponse:error:));
        if (m) {
            orig_sendSync = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_sendSync);
            LOG(@"Hooked NSURLConnection sendSynchronousRequest:");
        }
    }

    LOG(@"初始化完成");
}

__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun Bypass 网络拦截版 已加载");
    LOG(@"========================================");

    // 延迟初始化，确保网络框架已加载
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        doInit();
    });
}
