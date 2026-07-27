//
//  iphook.m - KFun 极简记录版 v4-fix
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunV4] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 15000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 15000)];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = g_logBuffer;
            [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)];
        }
    });
}

@interface LogDragHandler : NSObject
@end
@implementation LogDragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view.superview;
    CGPoint t = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + t.x, view.center.y + t.y);
    [pan setTranslation:CGPointZero inView:view.superview];
}
- (void)copyLog:(id)sender {
    if (g_logBuffer && g_logBuffer.length > 0) {
        UIPasteboard.generalPasteboard.string = g_logBuffer;
        LOG(@"📋 已复制 (%lu 字符)", (unsigned long)g_logBuffer.length);
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
        
        CGFloat w = 320, h = 220;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(8, 100, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.9];
        g_logContainer.layer.cornerRadius = 8;
        g_logContainer.layer.borderColor = [UIColor cyanColor].CGColor;
        g_logContainer.layer.borderWidth = 1;
        
        UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 24)];
        titleBar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        [g_logContainer addSubview:titleBar];
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(6, 2, w-70, 20)];
        title.text = @"🔍 KFun v4 (拖动)";
        title.textColor = [UIColor cyanColor];
        title.font = [UIFont boldSystemFontOfSize:9];
        [titleBar addSubview:title];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w-60, 2, 55, 20);
        [copyBtn setTitle:@"📋复制" forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont systemFontOfSize:8];
        [copyBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        g_dragHandler = [[LogDragHandler alloc] init];
        [copyBtn addTarget:g_dragHandler action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [titleBar addSubview:copyBtn];
        
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 26, w-4, h-28)];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:7];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = YES;
        [g_logContainer addSubview:g_logView];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_dragHandler action:@selector(handlePan:)];
        [titleBar addGestureRecognizer:pan];
        
        [keyWindow addSubview:g_logContainer];
        LOG(@"✅ v4 已启动");
    });
}

// ============================================================
// 极简网络记录
// ============================================================
static void recordNetwork() {
    Class cls = [NSURLSession class];
    
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *typeEnc = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURL *url, id completion) {
            LOG(@"🌐 GET %@", url.absoluteString);
            id wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
                if (data && data.length < 2000) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    LOG(@"🌐 RESP %ld | %@ | %@", (long)(http?http.statusCode:0), url.absoluteString, body?body:@"[bin]");
                } else {
                    LOG(@"🌐 RESP %ld | %@ | [%lu bytes]", (long)(http?http.statusCode:0), url.absoluteString, (unsigned long)(data?data.length:0));
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, response, error);
            };
            return ((id (*)(id, SEL, NSURL*, id))orig)(self, @selector(dataTaskWithURL:completionHandler:), url, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithURL:completionHandler:), newIMP, typeEnc);
    }
    
    Method m2 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *typeEnc = method_getTypeEncoding(m2);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURLRequest *req, id completion) {
            if (req.HTTPBody && req.HTTPBody.length < 1000) {
                NSString *body = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
                LOG(@"🌐 POST %@ | %@", req.URL.absoluteString, body?body:@"[bin]");
            } else {
                LOG(@"🌐 POST %@ | [%lu bytes]", req.URL.absoluteString, (unsigned long)(req.HTTPBody?req.HTTPBody.length:0));
            }
            id wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
                if (data && data.length < 2000) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    LOG(@"🌐 RESP %ld | %@ | %@", (long)(http?http.statusCode:0), req.URL.absoluteString, body?body:@"[bin]");
                } else {
                    LOG(@"🌐 RESP %ld | %@ | [%lu bytes]", (long)(http?http.statusCode:0), req.URL.absoluteString, (unsigned long)(data?data.length:0));
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, response, error);
            };
            return ((id (*)(id, SEL, NSURLRequest*, id))orig)(self, @selector(dataTaskWithRequest:completionHandler:), req, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithRequest:completionHandler:), newIMP, typeEnc);
    }
    LOG(@"✅ 网络记录");
}

// ============================================================
// 轻量属性快照（只打印关键属性）
// ============================================================
static void snap(id obj, NSString *label) {
    if (!obj) return;
    LOG(@"📸 [%@]", label);
    NSArray *keys = @[@"state", @"tableView", @"langSeg", @"statusText", @"dataText", @"onVerify", @"busy", @"successView"];
    for (NSString *k in keys) {
        @try {
            id v = [obj valueForKey:k];
            NSString *d = v ? [v description] : @"nil";
            if (d.length > 80) d = [d substringToIndex:80];
            LOG(@"  %@=%@", k, d);
        } @catch (NSException *e) {}
    }
}

// ============================================================
// Hook 入口
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"[KFunV4] 极简记录版启动");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        recordNetwork();
        
        // Hook ActVC
        Class actVC = objc_getClass("WWWActivationViewController");
        if (actVC) {
            Method m;
            
            m = class_getInstanceMethod(actVC, @selector(onTapVerify));
            if (m) {
                IMP orig = method_getImplementation(m);
                const char *te = method_getTypeEncoding(m);
                IMP ni = imp_implementationWithBlock(^(id self) {
                    LOG(@"🎯 onTapVerify");
                    snap(self, @"ActVC(点击前)");
                    ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
                    snap(self, @"ActVC(点击后)");
                });
                class_replaceMethod(actVC, @selector(onTapVerify), ni, te);
            }
            
            m = class_getInstanceMethod(actVC, @selector(showSuccess:completion:));
            if (m) {
                IMP orig = method_getImplementation(m);
                const char *te = method_getTypeEncoding(m);
                IMP ni = imp_implementationWithBlock(^(id self, id e, id c) {
                    LOG(@"🎉 showSuccess expire=%@ completion=%@", e, c?NSStringFromClass([c class]):@"nil");
                    snap(self, @"ActVC(showSuccess前)");
                    ((void (*)(id, SEL, id, id))orig)(self, @selector(showSuccess:completion:), e, c);
                    LOG(@"🎉 showSuccess完毕");
                    snap(self, @"ActVC(showSuccess后)");
                });
                class_replaceMethod(actVC, @selector(showSuccess:completion:), ni, te);
            }
            
            m = class_getInstanceMethod(actVC, @selector(buildSuccessViewWithExpire:));
            if (m) {
                IMP orig = method_getImplementation(m);
                const char *te = method_getTypeEncoding(m);
                IMP ni = imp_implementationWithBlock(^(id self, id e) {
                    LOG(@"🏗 buildSuccessView expire=%@", e);
                    ((void (*)(id, SEL, id))orig)(self, @selector(buildSuccessViewWithExpire:), e);
                });
                class_replaceMethod(actVC, @selector(buildSuccessViewWithExpire:), ni, te);
            }
            LOG(@"✅ ActVC hooked");
        }
        
        // Hook MainVC（只 hook viewDidAppear + 轮询 state）
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) {
            Method m = class_getInstanceMethod(mainVC, @selector(viewDidAppear:));
            if (m) {
                IMP orig = method_getImplementation(m);
                const char *te = method_getTypeEncoding(m);
                IMP ni = imp_implementationWithBlock(^(id self, BOOL a) {
                    LOG(@"🎯 MainVC viewDidAppear");
                    snap(self, @"MainVC(didAppear)");
                    ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), a);
                });
                class_replaceMethod(mainVC, @selector(viewDidAppear:), ni, te);
            }
            LOG(@"✅ MainVC hooked");
        }
        
        // 轻量轮询：只检测 state 变化
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            static NSInteger lastState = -1;
            static id lastMainVC = nil;
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
            #pragma clang diagnostic pop
                UIViewController *r = w.rootViewController;
                if ([r isKindOfClass:mainVC]) {
                    if (r != lastMainVC) {
                        lastMainVC = r;
                        lastState = -1;
                        LOG(@"🔔 MainVC 实例切换");
                    }
                    @try {
                        NSInteger s = [[r valueForKey:@"state"] integerValue];
                        if (s != lastState) {
                            LOG(@"🔔 state: %ld -> %ld", (long)lastState, (long)s);
                            snap(r, [NSString stringWithFormat:@"MainVC(state=%ld)", (long)s]);
                            lastState = s;
                        }
                    } @catch (NSException *e) {}
                    break;
                }
            }
        }];
        
        LOG(@"🚀 操作：输入真卡密 → 点验证 → 等主页面内容完全显示 → 点复制");
    });
}
