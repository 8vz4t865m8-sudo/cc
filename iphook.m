//
//  iphook.m - KFun Bypass v14
//  精简版：仅伪造激活成功，保留原始后续流程
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

// ============================================================
// 调试悬浮窗（保留，方便观察）
// ============================================================
static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunV14] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    @synchronized (g_logBuffer) {
        [g_logBuffer appendFormat:@"%@\n", line];
        if (g_logBuffer.length > 15000) {
            [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 15000)];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = g_logBuffer;
            [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)];
        }
    });
}

@interface LogDragHandler : NSObject @end
@implementation LogDragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view.superview;
    CGPoint t = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + t.x, view.center.y + t.y);
    [pan setTranslation:CGPointZero inView:view.superview];
}
- (void)copyLog:(id)sender {
    @synchronized (g_logBuffer) {
        if (g_logBuffer && g_logBuffer.length > 0) {
            UIPasteboard.generalPasteboard.string = g_logBuffer;
            LOG(@"📋 已复制 (%lu 字符)", (unsigned long)g_logBuffer.length);
        }
    }
}
@end
static LogDragHandler *g_dragHandler = nil;

static void setupLogWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)scene).activationState == UISceneActivationStateForegroundActive) {
                    if (((UIWindowScene *)scene).windows.count > 0) { keyWindow = ((UIWindowScene *)scene).windows.firstObject; break; }
                }
            }
        }
        if (!keyWindow) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
            if (!keyWindow && [UIApplication sharedApplication].windows.count > 0) keyWindow = [UIApplication sharedApplication].windows[0];
            #pragma clang diagnostic pop
        }
        if (!keyWindow) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupLogWindow(); }); return; }

        CGFloat w = 350, h = 300;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(8, 100, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.93];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor cyanColor].CGColor;
        g_logContainer.layer.borderWidth = 1.2;

        UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 28)];
        titleBar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        [g_logContainer addSubview:titleBar];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(6, 3, w-80, 22)];
        title.text = @"🔍 KFun v14 (拖动)";
        title.textColor = [UIColor cyanColor];
        title.font = [UIFont boldSystemFontOfSize:10];
        [titleBar addSubview:title];

        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w-70, 3, 65, 22);
        [copyBtn setTitle:@"📋复制" forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont systemFontOfSize:9];
        [copyBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        g_dragHandler = [[LogDragHandler alloc] init];
        [copyBtn addTarget:g_dragHandler action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [titleBar addSubview:copyBtn];

        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 30, w-4, h-32)];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:8];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = YES;
        [g_logContainer addSubview:g_logView];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_dragHandler action:@selector(handlePan:)];
        [titleBar addGestureRecognizer:pan];

        [keyWindow addSubview:g_logContainer];
        LOG(@"✅ 悬浮窗已启动");
    });
}

// ============================================================
// 🎯 核心：NSURLProtocol 拦截激活请求
// ============================================================
@interface FakeActivationProtocol : NSURLProtocol @end

@implementation FakeActivationProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *urlStr = request.URL.absoluteString.lowercaseString;
    // 根据实际抓包调整匹配规则，可添加多个关键词
    if ([urlStr containsString:@"activate"] || 
        [urlStr containsString:@"verify"] ||
        [urlStr containsString:@"activation"]) {
        LOG(@"🔁 拦截激活请求: %@", request.URL.absoluteString);
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    // 构造伪造的成功响应 JSON
    NSDictionary *fakeDict = @{
        @"code": @200,
        @"msg": @"success",
        @"expire": @"2099-12-31 23:59:59"   // ← 应用取到期时间的字段（请按实际调整）
    };
    NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeDict options:0 error:nil];
    
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": @"application/json"}];
    
    id<NSURLProtocolClient> client = self.client;
    [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [client URLProtocol:self didLoadData:fakeData];
    [client URLProtocolDidFinishLoading:self];
    
    LOG(@"✅ 伪造激活成功 (到期: 2099-12-31 23:59:59)");
}

- (void)stopLoading {
    // 无需处理
}

@end

// ============================================================
// Hook 部分：仅强制激活状态 + 主界面调试日志
// ============================================================
static void hookActivationVC(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
    LOG(@"🎣 轻量 Hook ActVC: %s", class_getName(cls));
    
    // 强制返回已激活/已验证
    Method m;
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
        class_replaceMethod(cls, @selector(isActivated), newIMP, method_getTypeEncoding(m));
        LOG(@"  ✅ isActivated -> YES");
    }
    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) {
        IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
        class_replaceMethod(cls, @selector(isVerified), newIMP, method_getTypeEncoding(m));
        LOG(@"  ✅ isVerified -> YES");
    }
    
    // 仅用于观察，不修改行为
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"👀 ActVC viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
        LOG(@"  ✅ viewDidLoad (仅记录)");
    }
}

static void hookMainVC(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 ViewController"); return; }
    LOG(@"🎣 观察 MainVC: %s", class_getName(cls));
    
    // viewDidLoad 仅记录
    Method m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"👀 MainVC viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
        LOG(@"  ✅ viewDidLoad (仅记录)");
    }
    
    // viewDidAppear 仅记录
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"👀 MainVC viewDidAppear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
        });
        class_replaceMethod(cls, @selector(viewDidAppear:), newIMP, typeEnc);
        LOG(@"  ✅ viewDidAppear: (仅记录)");
    }
}

// ============================================================
// 初始化入口
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"[KFunV14] 仅伪造激活成功版本已加载");
    
    // 1. 立即注册 NSURLProtocol（主线程/当前线程均可）
    [NSURLProtocol registerClass:[FakeActivationProtocol class]];
    LOG(@"✅ NSURLProtocol 已注册，激活请求将被拦截");
    
    // 2. 延迟设置日志窗口（等待 keyWindow 就绪）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        
        // 3. 轻量 Hook
        Class actVC = objc_getClass("WWWActivationViewController");
        if (actVC) hookActivationVC(actVC);
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookMainVC(mainVC);
        
        LOG(@"🚀 初始化完成，等待应用发起激活请求...");
    });
}
