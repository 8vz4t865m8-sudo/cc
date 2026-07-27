//
//  kfun_observer.m
//  KFun 零干扰观察器 - 纯记录，不拦截
//  编译: clang -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//        -framework UIKit -framework Foundation \
//        -dynamiclib -o kfun_observer.dylib kfun_observer.m
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 日志系统

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;
static NSDateFormatter *g_df = nil;

static NSString* ts(void) {
    if (!g_df) {
        g_df = [[NSDateFormatter alloc] init];
        g_df.dateFormat = @"HH:mm:ss.SSS";
    }
    return [g_df stringFromDate:[NSDate date]];
}

static void logRaw(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts(), msg];
    NSLog(@"[KFunO] %@", line);
    
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendString:line];
    if (g_logBuffer.length > 30000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 30000)];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = g_logBuffer;
            [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)];
        }
    });
}

#pragma mark - 悬浮窗

@interface DragHandler : NSObject
@end
@implementation DragHandler

- (UIWindow *)keyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)s).activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *ws = (UIWindowScene *)s;
                if (ws.windows.count) return ws.windows.firstObject;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
#pragma clang diagnostic pop
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view.superview;
    CGPoint t = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}

- (void)copyLog:(id)sender {
    if (g_logBuffer.length) {
        UIPasteboard.generalPasteboard.string = g_logBuffer;
        logRaw(@"📋 已复制 (%lu 字符)", (unsigned long)g_logBuffer.length);
    }
}

- (void)clearLog:(id)sender {
    [g_logBuffer setString:@""];
    g_logView.text = @"";
}

@end

static DragHandler *g_drag = nil;

static void setupWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DragHandler *dh = [[DragHandler alloc] init];
        g_drag = dh;
        UIWindow *kw = [dh keyWindow];
        if (!kw) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupWindow(); });
            return;
        }
        
        CGFloat w = 360, h = 280;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(6, 90, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.92];
        g_logContainer.layer.cornerRadius = 8;
        g_logContainer.layer.borderColor = [UIColor cyanColor].CGColor;
        g_logContainer.layer.borderWidth = 1;
        
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 26)];
        bar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        [g_logContainer addSubview:bar];
        
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(6, 3, 180, 20)];
        t.text = @"🔬 KFun Observer";
        t.textColor = [UIColor cyanColor];
        t.font = [UIFont boldSystemFontOfSize:10];
        [bar addSubview:t];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w-70, 2, 65, 22);
        [copyBtn setTitle:@">📋复制" forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont systemFontOfSize:10];
        [copyBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        [copyBtn addTarget:dh action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:copyBtn];
        
        UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        clearBtn.frame = CGRectMake(w-130, 2, 55, 22);
        [clearBtn setTitle:@">🧹清空" forState:UIControlStateNormal];
        clearBtn.titleLabel.font = [UIFont systemFontOfSize:10];
        [clearBtn setTitleColor:[UIColor orangeColor] forState:UIControlStateNormal];
        [clearBtn addTarget:dh action:@selector(clearLog:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:clearBtn];
        
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 28, w-4, h-30)];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:8];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = YES;
        [g_logContainer addSubview:g_logView];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:dh action:@selector(handlePan:)];
        [bar addGestureRecognizer:pan];
        
        [kw addSubview:g_logContainer];
        logRaw(@"✅ 观察器启动 - 零干扰模式");
    });
}

#pragma mark - 属性快照（轻量）

static void snap(id obj, NSString *label) {
    if (!obj) return;
    logRaw(@"📸 [%@] %@", label, NSStringFromClass([obj class]));
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count && i < 30; i++) {  // 限制30个属性，防卡
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            id val = [obj valueForKey:name];
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 80) desc = [desc substringToIndex:80];
            logRaw(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {}
    }
    if (props) free(props);
}

#pragma mark - 网络观察（只记录，不拦截）

static void observeNetwork(void) {
    Class cls = [NSURLSession class];
    
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURL *url, id completion) {
            logRaw(@"🌐 GET %@", url.absoluteString);
            id wrapped = ^(NSData *data, NSURLResponse *resp, NSError *err) {
                NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
                logRaw(@"🌐 RES %@ | %ld | %@", url.absoluteString, (long)(http?http.statusCode:0), err?err.localizedDescription:@"ok");
                if (data && data.length < 1500) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (body && body.length < 500) logRaw(@"🌐 BODY %@", body);
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, resp, err);
            };
            return ((id (*)(id, SEL, NSURL*, id))orig)(self, @selector(dataTaskWithURL:completionHandler:), url, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithURL:completionHandler:), newIMP, te);
    }
    
    Method m2 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSURLRequest *req, id completion) {
            NSString *bodyStr = nil;
            if (req.HTTPBody) {
                bodyStr = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
                if (!bodyStr) bodyStr = [req.HTTPBody base64EncodedStringWithOptions:0];
            }
            logRaw(@"🌐 REQ %@ %@ | body=%@", req.HTTPMethod, req.URL.absoluteString, bodyStr ?: @"nil");
            id wrapped = ^(NSData *data, NSURLResponse *resp, NSError *err) {
                NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
                logRaw(@"🌐 RES %@ | %ld | %@", req.URL.absoluteString, (long)(http?http.statusCode:0), err?err.localizedDescription:@"ok");
                if (data && data.length < 1500) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (body && body.length < 500) logRaw(@"🌐 BODY %@", body);
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, resp, err);
            };
            return ((id (*)(id, SEL, NSURLRequest*, id))orig)(self, @selector(dataTaskWithRequest:completionHandler:), req, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithRequest:completionHandler:), newIMP, te);
    }
    
    logRaw(@"✅ 网络观察启用");
}

#pragma mark - 通知观察（只记录）

static void observeNotifications(void) {
    Class nc = [NSNotificationCenter class];
    
    Method m1 = class_getInstanceMethod(nc, @selector(postNotificationName:object:userInfo:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *name, id obj, NSDictionary *info) {
            logRaw(@"📢 POST %@ | info=%@", name, info);
            ((void (*)(id, SEL, NSString*, id, NSDictionary*))orig)(self, @selector(postNotificationName:object:userInfo:), name, obj, info);
        });
        class_replaceMethod(nc, @selector(postNotificationName:object:userInfo:), newIMP, te);
    }
    
    logRaw(@"✅ 通知观察启用");
}

#pragma mark - UserDefaults 观察（只记录，不改值）

static void observeDefaults(void) {
    Class ud = [NSUserDefaults class];
    
    Method m1 = class_getInstanceMethod(ud, @selector(setObject:forKey:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, id val, NSString *key) {
            NSString *desc = [val description];
            if (desc.length > 100) desc = [desc substringToIndex:100];
            logRaw(@"💾 SET %@ = %@", key, desc);
            ((void (*)(id, SEL, id, NSString*))orig)(self, @selector(setObject:forKey:), val, key);
        });
        class_replaceMethod(ud, @selector(setObject:forKey:), newIMP, te);
    }
    
    Method m2 = class_getInstanceMethod(ud, @selector(objectForKey:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *key) {
            id val = ((id (*)(id, SEL, NSString*))orig)(self, @selector(objectForKey:), key);
            logRaw(@"💾 GET %@ = %@", key, val ? @"有值" : @"nil");
            return val;
        });
        class_replaceMethod(ud, @selector(objectForKey:), newIMP, te);
    }
    
    logRaw(@"✅ UD观察启用");
}

#pragma mark - 生命周期观察（只快照，不拦截）

static void observeLifecycle(void) {
    // ActVC - 只观察 viewDidLoad 和 dealloc，不碰验证方法
    Class actVC = objc_getClass("WWWActivationViewController");
    if (actVC) {
        Method m = class_getInstanceMethod(actVC, @selector(viewDidLoad));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                logRaw(@"🎯 [ActVC] viewDidLoad");
                ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
                snap(self, @"ActVC");
            });
            class_replaceMethod(actVC, @selector(viewDidLoad), newIMP, te);
        }
        logRaw(@"🎣 ActVC 已观察");
    }
    
    // MainVC
    Class mainVC = objc_getClass("ViewController");
    if (mainVC) {
        Method m = class_getInstanceMethod(mainVC, @selector(viewDidLoad));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                logRaw(@"🎯 [MainVC] viewDidLoad");
                ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
                snap(self, @"MainVC");
            });
            class_replaceMethod(mainVC, @selector(viewDidLoad), newIMP, te);
        }
        
        m = class_getInstanceMethod(mainVC, @selector(viewDidAppear:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, BOOL anim) {
                logRaw(@"🎯 [MainVC] viewDidAppear:");
                ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), anim);
                snap(self, @"MainVC-appear");
            });
            class_replaceMethod(mainVC, @selector(viewDidAppear:), newIMP, te);
        }
        logRaw(@"🎣 MainVC 已观察");
    }
}

#pragma mark - 入口

__attribute__((constructor))
static void kfun_observer_init() {
    NSLog(@"[KFunO] 观察器加载");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWindow();
        observeNetwork();
        observeNotifications();
        observeDefaults();
        observeLifecycle();
        
        logRaw(@"🚀 零干扰观察器就绪");
        logRaw(@"📋 请用正版卡密正常验证");
        logRaw(@"📋 验证通过后点 📋复制 导出日志");
    });
}
