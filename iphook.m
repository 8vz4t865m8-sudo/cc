//
//  kfun_analyzer.m
//  KFun 动态分析器 - 无越狱 iOS 18.4 可用
//  编译: clang -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//        -framework UIKit -framework Foundation \
//        -dynamiclib -o kfun_analyzer.dylib kfun_analyzer.m
//  使用: DYLD_INSERT_LIBRARIES=kfun_analyzer.dylib /path/to/kfun.app/kfun
//       或通过 TrollStore / 侧载注入
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - ===== 日志系统 =====

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;
static NSDateFormatter *g_df = nil;
static UILabel *g_statusLabel = nil;

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
    NSLog(@"[KFunA] %@", line);
    
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendString:line];
    if (g_logBuffer.length > 50000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 50000)];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = g_logBuffer;
            [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)];
        }
    });
}

#pragma mark - ===== 悬浮窗控制器 =====

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
        logRaw(@"📋 日志已复制 (%lu 字符)", (unsigned long)g_logBuffer.length);
    }
}

- (void)clearLog:(id)sender {
    [g_logBuffer setString:@""];
    g_logView.text = @"";
    logRaw(@"🧹 已清空");
}

- (void)dumpHierarchy:(id)sender {
    UIWindow *kw = [self keyWindow];
    if (kw) {
        logRaw(@"🏗️ === 视图层级 ===");
        [self dumpView:kw depth:0];
        logRaw(@"🏗️ === 结束 ===");
    }
}

- (void)dumpView:(UIView *)v depth:(int)d {
    NSString *pad = [@"" stringByPaddingToLength:d*2 withString:@" " startingAtIndex:0];
    logRaw(@"%@[%@] frame=%@ hidden=%d alpha=%.1f subviews=%lu",
           pad, NSStringFromClass([v class]),
           NSStringFromCGRect(v.frame), (int)v.hidden, v.alpha, (unsigned long)v.subviews.count);
    for (UIView *sub in v.subviews) [self dumpView:sub depth:d+1];
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
        
        CGFloat w = 380, h = 340;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(6, 90, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.94];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0].CGColor;
        g_logContainer.layer.borderWidth = 1.5;
        
        // 标题栏
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 32)];
        bar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        [g_logContainer addSubview:bar];
        
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(6, 4, 200, 24)];
        t.text = @"🔬 KFun Analyzer v2.1";
        t.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
        t.font = [UIFont boldSystemFontOfSize:10];
        [bar addSubview:t];
        
        // 按钮定义: [标题, selector字符串]
        NSArray *btns = @[
            @[@">📋复制", @"copyLog:"],
            @[@">🧹清空", @"clearLog:"],
            @[@">🏗层级", @"dumpHierarchy:"],
        ];
        CGFloat bx = w - 4 - (btns.count * 50);
        for (NSArray *arr in btns) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(bx, 2, 48, 28);
            [b setTitle:arr[0] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:10];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [b addTarget:dh action:NSSelectorFromString(arr[1]) forControlEvents:UIControlEventTouchUpInside];
            [bar addSubview:b];
            bx += 50;
        }
        
        // 状态标签
        g_statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 34, w-12, 16)];
        g_statusLabel.text = @"🟢网络 🟢通知 🟢缓存";
        g_statusLabel.textColor = [UIColor lightGrayColor];
        g_statusLabel.font = [UIFont systemFontOfSize:8];
        [g_logContainer addSubview:g_statusLabel];
        
        // 日志区
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(2, 52, w-4, h-54)];
        g_logView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
        g_logView.font = [UIFont fontWithName:@"Menlo" size:8];
        g_logView.backgroundColor = [UIColor clearColor];
        g_logView.editable = NO;
        g_logView.selectable = YES;
        [g_logContainer addSubview:g_logView];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:dh action:@selector(handlePan:)];
        [bar addGestureRecognizer:pan];
        
        [kw addSubview:g_logContainer];
        logRaw(@"✅ 分析器已启动");
    });
}

#pragma mark - ===== 属性快照 =====

static void snapshotObj(id obj, NSString *label) {
    if (!obj) { logRaw(@"❌ [%@] nil", label); return; }
    logRaw(@"📸 === %@ (%@) ===", label, NSStringFromClass([obj class]));
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            id val = [obj valueForKey:name];
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 120) desc = [desc substringToIndex:120];
            logRaw(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {
            logRaw(@"   %@ = [ERR:%@]", name, e.reason);
        }
    }
    if (props) free(props);
    logRaw(@"📸 === End ===");
}

#pragma mark - ===== 网络拦截 =====

static void hookNetwork(void) {
    Class cls = [NSURLSession class];
    
    // dataTaskWithURL:completionHandler:
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (m1) {
        IMP orig1 = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP new1 = imp_implementationWithBlock(^(id self, NSURL *url, id completion) {
            logRaw(@"🌐 [GET] %@", url.absoluteString);
            id wrapped = ^(NSData *data, NSURLResponse *resp, NSError *err) {
                NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
                logRaw(@"🌐 [RES] %@ | Status:%ld | Err:%@",
                       url.absoluteString, (long)(http?http.statusCode:0), err?err.localizedDescription:@"nil");
                if (data) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (body) {
                        NSString *trim = body.length > 600 ? [body substringToIndex:600] : body;
                        logRaw(@"🌐 [BODY] %@", trim);
                    }
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, resp, err);
            };
            return ((id (*)(id, SEL, NSURL*, id))orig1)(self, @selector(dataTaskWithURL:completionHandler:), url, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithURL:completionHandler:), new1, te);
    }
    
    // dataTaskWithRequest:completionHandler:
    Method m2 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m2) {
        IMP orig2 = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP new2 = imp_implementationWithBlock(^(id self, NSURLRequest *req, id completion) {
            NSString *bodyStr = nil;
            if (req.HTTPBody) {
                bodyStr = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
                if (!bodyStr) bodyStr = [req.HTTPBody base64EncodedStringWithOptions:0];
            }
            logRaw(@"🌐 [REQ] %@ | %@ | Headers:%@ | Body:%@",
                   req.URL.absoluteString, req.HTTPMethod,
                   req.allHTTPHeaderFields, bodyStr ?: @"nil");
            id wrapped = ^(NSData *data, NSURLResponse *resp, NSError *err) {
                NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
                logRaw(@"🌐 [RES] %@ | Status:%ld | Err:%@",
                       req.URL.absoluteString, (long)(http?http.statusCode:0), err?err.localizedDescription:@"nil");
                if (data) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (body) {
                        NSString *trim = body.length > 600 ? [body substringToIndex:600] : body;
                        logRaw(@"🌐 [BODY] %@", trim);
                    }
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, resp, err);
            };
            return ((id (*)(id, SEL, NSURLRequest*, id))orig2)(self, @selector(dataTaskWithRequest:completionHandler:), req, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithRequest:completionHandler:), new2, te);
    }
    
    logRaw(@"✅ 网络拦截已启用");
}

#pragma mark - ===== 通知中心拦截 =====

static void hookNotifications(void) {
    Class nc = [NSNotificationCenter class];
    
    Method m1 = class_getInstanceMethod(nc, @selector(postNotificationName:object:userInfo:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *name, id obj, NSDictionary *info) {
            logRaw(@"📢 [Notify] post: %@ | obj=%@ | info=%@", name, obj, info);
            ((void (*)(id, SEL, NSString*, id, NSDictionary*))orig)(self, @selector(postNotificationName:object:userInfo:), name, obj, info);
        });
        class_replaceMethod(nc, @selector(postNotificationName:object:userInfo:), newIMP, te);
    }
    
    Method m2 = class_getInstanceMethod(nc, @selector(postNotification:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSNotification *n) {
            logRaw(@"📢 [Notify] postNotification: %@", n);
            ((void (*)(id, SEL, NSNotification*))orig)(self, @selector(postNotification:), n);
        });
        class_replaceMethod(nc, @selector(postNotification:), newIMP, te);
    }
    
    logRaw(@"✅ 通知拦截已启用");
}

#pragma mark - ===== NSUserDefaults 拦截 =====

static void hookUserDefaults(void) {
    Class ud = [NSUserDefaults class];
    
    Method m1 = class_getInstanceMethod(ud, @selector(setObject:forKey:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, id val, NSString *key) {
            NSString *desc = [val description];
            if (desc.length > 200) desc = [desc substringToIndex:200];
            logRaw(@"💾 [UD set] %@ = %@", key, desc);
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
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 200) desc = [desc substringToIndex:200];
            logRaw(@"💾 [UD get] %@ = %@", key, desc);
            return val;
        });
        class_replaceMethod(ud, @selector(objectForKey:), newIMP, te);
    }
    
    Method m3 = class_getInstanceMethod(ud, @selector(setBool:forKey:));
    if (m3) {
        IMP orig = method_getImplementation(m3);
        const char *te = method_getTypeEncoding(m3);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL val, NSString *key) {
            logRaw(@"💾 [UD setBool] %@ = %d", key, val);
            ((void (*)(id, SEL, BOOL, NSString*))orig)(self, @selector(setBool:forKey:), val, key);
        });
        class_replaceMethod(ud, @selector(setBool:forKey:), newIMP, te);
    }
    
    Method m4 = class_getInstanceMethod(ud, @selector(setInteger:forKey:));
    if (m4) {
        IMP orig = method_getImplementation(m4);
        const char *te = method_getTypeEncoding(m4);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSInteger val, NSString *key) {
            logRaw(@"💾 [UD setInt] %@ = %ld", key, (long)val);
            ((void (*)(id, SEL, NSInteger, NSString*))orig)(self, @selector(setInteger:forKey:), val, key);
        });
        class_replaceMethod(ud, @selector(setInteger:forKey:), newIMP, te);
    }
    
    logRaw(@"✅ UserDefaults 拦截已启用");
}

#pragma mark - ===== 关键类 Hook =====

static void hookCriticalClasses(void) {
    // ActVC 关键方法
    Class actVC = objc_getClass("WWWActivationViewController");
    if (actVC) {
        logRaw(@"🎣 找到 WWWActivationViewController");
        
        Method m = class_getInstanceMethod(actVC, @selector(viewDidLoad));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                logRaw(@"🎯 [ActVC] viewDidLoad 开始");
                ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
                snapshotObj(self, @"ActVC(viewDidLoad后)");
                logRaw(@"🎯 [ActVC] viewDidLoad 结束");
            });
            class_replaceMethod(actVC, @selector(viewDidLoad), newIMP, te);
        }
        
        m = class_getInstanceMethod(actVC, @selector(onTapVerify));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                logRaw(@"🎯 [ActVC] onTapVerify 触发");
                snapshotObj(self, @"ActVC(onTapVerify前)");
                ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
                snapshotObj(self, @"ActVC(onTapVerify后)");
            });
            class_replaceMethod(actVC, @selector(onTapVerify), newIMP, te);
        }
        
        m = class_getInstanceMethod(actVC, @selector(showSuccess:completion:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg, id completion) {
                logRaw(@"🎯 [ActVC] showSuccess: %@ | completion=%@", msg, completion);
                id wrapped = ^(void) {
                    logRaw(@"🎉 [ActVC] completion 执行！");
                    if (completion) ((void(^)(void))completion)();
                    snapshotObj(self, @"ActVC(completion后)");
                };
                ((void (*)(id, SEL, NSString*, id))orig)(self, @selector(showSuccess:completion:), msg, wrapped);
            });
            class_replaceMethod(actVC, @selector(showSuccess:completion:), newIMP, te);
        }
        
        m = class_getInstanceMethod(actVC, @selector(setupAfterActivation));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                logRaw(@"🎯 [ActVC] setupAfterActivation 调用");
                ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
                snapshotObj(self, @"ActVC(setupAfterActivation后)");
            });
            class_replaceMethod(actVC, @selector(setupAfterActivation), newIMP, te);
        }
        
        m = class_getInstanceMethod(actVC, @selector(showError:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
                logRaw(@"🛡️ [ActVC] showError 拦截: %@", msg);
                ((void (*)(id, SEL, NSString*))orig)(self, @selector(showError:), msg);
            });
            class_replaceMethod(actVC, @selector(showError:), newIMP, te);
        }
    }
    
    // MainVC 关键方法
    Class mainVC = objc_getClass("ViewController");
    if (mainVC) {
        logRaw(@"🎣 找到 ViewController");
        
        Method m = class_getInstanceMethod(mainVC, @selector(viewDidLoad));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                logRaw(@"🎯 [MainVC] viewDidLoad 开始");
                ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
                snapshotObj(self, @"MainVC(viewDidLoad后)");
                logRaw(@"🎯 [MainVC] viewDidLoad 结束");
            });
            class_replaceMethod(mainVC, @selector(viewDidLoad), newIMP, te);
        }
        
        m = class_getInstanceMethod(mainVC, @selector(viewDidAppear:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, BOOL anim) {
                logRaw(@"🎯 [MainVC] viewDidAppear: 开始");
                ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), anim);
                snapshotObj(self, @"MainVC(viewDidAppear后)");
                logRaw(@"🎯 [MainVC] viewDidAppear: 结束");
            });
            class_replaceMethod(mainVC, @selector(viewDidAppear:), newIMP, te);
        }
    }
}

#pragma mark - ===== 入口 =====

__attribute__((constructor))
static void kfun_analyzer_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunA] 分析器已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWindow();
        hookNetwork();
        hookNotifications();
        hookUserDefaults();
        hookCriticalClasses();
        
        logRaw(@"🚀 初始化完成");
        logRaw(@"📋 使用正版卡密正常验证");
        logRaw(@"📋 重点观察: 💾[UD] 📢[Notify] 🌐[网络]");
        logRaw(@"📋 验证完成后点击 📋复制，粘贴出来分析");
    });
}
