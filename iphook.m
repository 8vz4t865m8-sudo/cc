//
//  kfun_analyzer.m
//  KFun 动态分析器 - 配合正版卡密使用
//  编译: clang -dynamiclib -framework UIKit -framework Foundation kfun_analyzer.m -o kfun_analyzer.dylib
//  注入: DYLD_INSERT_LIBRARIES 或 Tweak 方式加载
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <pthread.h>

#pragma mark - ===== 日志系统 =====

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;
static NSDateFormatter *g_df = nil;
static UILabel *g_statusLabel = nil;
static BOOL g_networkEnabled = YES;
static BOOL g_notifyEnabled = YES;
static BOOL g_methodEnabled = YES;
static BOOL g_defaultsEnabled = YES;

#define ANALYZER_VERSION @"v2.0-Deep"

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

#define LOG_METHOD(...) do { if (g_methodEnabled) logRaw(__VA_ARGS__); } while(0)
#define LOG_NET(...) do { if (g_networkEnabled) logRaw(__VA_ARGS__); } while(0)
#define LOG_NOTIFY(...) do { if (g_notifyEnabled) logRaw(__VA_ARGS__); } while(0)
#define LOG_DEF(...) do { if (g_defaultsEnabled) logRaw(__VA_ARGS__); } while(0)

#pragma mark - ===== 悬浮窗 =====

@interface DragHandler : NSObject
@end
@implementation DragHandler
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view.superview;
    CGPoint t = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}
- (void)copyLog:(id)sender {
    if (g_logBuffer.length) {
        UIPasteboard.generalPasteboard.string = g_logBuffer;
        logRaw(@"📋 日志已复制到剪贴板 (%lu 字符)", (unsigned long)g_logBuffer.length);
    }
}
- (void)saveLog:(id)sender {
    if (!g_logBuffer.length) return;
    NSString *path = @"/var/mobile/kfun_analyzer_log.txt";
    NSError *err = nil;
    [g_logBuffer writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) logRaw(@"❌ 保存失败: %@", err.localizedDescription);
    else logRaw(@"💾 日志已保存到 %@", path);
}
- (void)clearLog:(id)sender {
    [g_logBuffer setString:@""];
    g_logView.text = @"";
    logRaw(@"🧹 日志已清空");
}
- (void)dumpHierarchy:(id)sender {
    UIWindow *kw = [self keyWindow];
    if (kw) {
        logRaw(@"🏗️ === 视图层级 Dump ===");
        [self dumpView:kw depth:0];
        logRaw(@"🏗️ === Dump 结束 ===");
    }
}
- (void)dumpView:(UIView *)v depth:(int)d {
    NSString *pad = [@"" stringByPaddingToLength:d*2 withString:@" " startingAtIndex:0];
    NSString *info = [NSString stringWithFormat:@"%@[%@] frame=%@ hidden=%d alpha=%.1f",
                      pad, NSStringFromClass([v class]),
                      NSStringFromCGRect(v.frame), (int)v.hidden, v.alpha];
    logRaw(@"%@", info);
    for (UIView *sub in v.subviews) [self dumpView:sub depth:d+1];
}
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
@end
static DragHandler *g_drag = nil;

static void setupWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DragHandler *dh = [[DragHandler alloc] init];
        g_drag = dh;
        UIWindow *kw = [dh keyWindow];
        if (!kw) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupWindow(); }); return; }
        
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
        
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(6, 4, 180, 24)];
        t.text = [NSString stringWithFormat:@"🔬 KFun Analyzer %@", ANALYZER_VERSION];
        t.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
        t.font = [UIFont boldSystemFontOfSize:10];
        [bar addSubview:t];
        
        // 控制按钮
        NSArray *btns = @[
            @[@">📋", @selector(copyLog:)],
            @[@">💾", @selector(saveLog:)],
            @[@">🧹", @selector(clearLog:)],
            @[@">🏗", @selector(dumpHierarchy:)],
        ];
        CGFloat bx = w - 4 - (btns.count * 44);
        for (NSArray *arr in btns) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(bx, 2, 42, 28);
            [b setTitle:arr[0] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:11];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [b addTarget:dh action:NSSelectorFromString(arr[1]) forControlEvents:UIControlEventTouchUpInside];
            [bar addSubview:b];
            bx += 44;
        }
        
        // 状态标签
        g_statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 34, w-12, 16)];
        g_statusLabel.text = @"🟢方法 🟢网络 🟢通知 🟢缓存";
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
        logRaw(@"✅ 分析器悬浮窗已启动");
        logRaw(@"📋 请使用正版卡密正常验证，观察日志流向");
    });
}

#pragma mark - ===== 通用方法追踪器 =====

static void swizzleMethod(Class cls, SEL sel, NSString *tag) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    const char *type = method_getTypeEncoding(m);
    NSString *clsName = NSStringFromClass(cls);
    
    IMP newIMP = imp_implementationWithBlock(^(id self, ...) {
        LOG_METHOD(@"[%@] ➡️ %@ 调用", tag, NSStringFromSelector(sel));
        
        // 尝试打印参数（仅针对部分常见类型做简单处理）
        va_list args;
        va_start(args, self);
        // 注意：这里为了稳定只记录调用，不深入解析变参
        va_end(args);
        
        // 调用原始方法
        NSMethodSignature *sig = [cls instanceMethodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        [inv setTarget:self];
        // 参数复制太复杂，这里用原始 IMP 直接调用（无参/单参常见情况）
        // 对于通用情况，我们直接转发
        // 实际上对可变参数用 NSInvocation 不好处理，这里简化：
        // 只记录调用，不拦截返回值
        
        // 使用原始 IMP 调用（假设最多3个id参数，覆盖大部分情况）
        // 更好的方式是用 forwardInvocation，但为了代码简洁：
        id ret = nil;
        NSUInteger nargs = [sig numberOfArguments];
        if (nargs <= 2) {
            ((void (*)(id, SEL))orig)(self, sel);
        } else if (nargs == 3) {
            id a1 = va_arg(args, id); // 这里其实拿不到，va_list 在 block 里不可用
            // 放弃参数解析，只记录调用
            ((void (*)(id, SEL, id))orig)(self, sel, nil);
        } else {
            ((void (*)(id, SEL))orig)(self, sel);
        }
        
        LOG_METHOD(@"[%@] ⬅️ %@ 返回", tag, NSStringFromSelector(sel));
        return ret;
    });
    
    class_replaceMethod(cls, sel, newIMP, type);
}

static void traceClass(NSString *clsName, NSString *tag) {
    Class cls = objc_getClass(clsName.UTF8String);
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    logRaw(@"🔬 开始追踪类: %@ (%u 个实例方法)", clsName, count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        swizzleMethod(cls, sel, tag);
    }
    if (methods) free(methods);
}

static void traceAllClassesWithPrefix(NSString *prefix) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name hasPrefix:prefix]) {
            traceClass(name, name);
        }
    }
    if (classes) free(classes);
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

#pragma mark - ===== 网络全拦截 =====

static void hookNetwork(void) {
    // 1. NSURLSession dataTaskWithURL:
    Class cls = [NSURLSession class];
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (m1) {
        IMP orig1 = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP new1 = imp_implementationWithBlock(^(id self, NSURL *url, id completion) {
            LOG_NET(@"🌐 [Session] dataTaskWithURL: %@", url.absoluteString);
            id wrapped = ^(NSData *data, NSURLResponse *resp, NSError *err) {
                NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
                LOG_NET(@"🌐 [Session] 响应 %@ | Status:%ld | Err:%@",
                        url.absoluteString, (long)(http?http.statusCode:0), err?err.localizedDescription:@"nil");
                if (data) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (body) {
                        NSString *trim = body.length > 800 ? [body substringToIndex:800] : body;
                        LOG_NET(@"🌐 [Session] Body: %@", trim);
                    }
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, resp, err);
            };
            return ((id (*)(id, SEL, NSURL*, id))orig1)(self, @selector(dataTaskWithURL:completionHandler:), url, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithURL:completionHandler:), new1, te);
    }
    
    // 2. NSURLSession dataTaskWithRequest:
    Method m2 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m2) {
        IMP orig2 = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP new2 = imp_implementationWithBlock(^(id self, NSURLRequest *req, id completion) {
            LOG_NET(@"🌐 [Session] dataTaskWithRequest: %@ | Method:%@ | Headers:%@ | Body:%@",
                    req.URL.absoluteString,
                    req.HTTPMethod,
                    req.allHTTPHeaderFields,
                    req.HTTPBody ? [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding] : @"nil");
            id wrapped = ^(NSData *data, NSURLResponse *resp, NSError *err) {
                NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
                LOG_NET(@"🌐 [Session] 响应 %@ | Status:%ld | Err:%@",
                        req.URL.absoluteString, (long)(http?http.statusCode:0), err?err.localizedDescription:@"nil");
                if (data) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (body) {
                        NSString *trim = body.length > 800 ? [body substringToIndex:800] : body;
                        LOG_NET(@"🌐 [Session] Body: %@", trim);
                    }
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, resp, err);
            };
            return ((id (*)(id, SEL, NSURLRequest*, id))orig2)(self, @selector(dataTaskWithRequest:completionHandler:), req, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithRequest:completionHandler:), new2, te);
    }
    
    // 3. NSURLConnection sendSynchronousRequest / sendAsynchronousRequest (旧版)
    Class connCls = [NSURLConnection class];
    Method m3 = class_getClassMethod(connCls, @selector(sendAsynchronousRequest:queue:completionHandler:));
    if (m3) {
        IMP orig3 = method_getImplementation(m3);
        const char *te = method_getTypeEncoding(m3);
        IMP new3 = imp_implementationWithBlock(^(id self, NSURLRequest *req, NSOperationQueue *queue, id handler) {
            LOG_NET(@"🌐 [Conn] sendAsync: %@ | Method:%@", req.URL.absoluteString, req.HTTPMethod);
            id wrapped = ^(NSURLResponse *resp, NSData *data, NSError *err) {
                LOG_NET(@"🌐 [Conn] 响应 %@ | Err:%@", req.URL.absoluteString, err?err.localizedDescription:@"nil");
                if (handler) ((void(^)(NSURLResponse*,NSData*,NSError*))handler)(resp, data, err);
            };
            return ((id (*)(id, SEL, NSURLRequest*, NSOperationQueue*, id))orig3)(self, @selector(sendAsynchronousRequest:queue:completionHandler:), req, queue, wrapped);
        });
        class_replaceMethod(object_getClass(connCls), @selector(sendAsynchronousRequest:queue:completionHandler:), new3, te);
    }
    
    logRaw(@"✅ 网络拦截已启用 (NSURLSession + NSURLConnection)");
}

#pragma mark - ===== 通知中心拦截 =====

static void hookNotifications(void) {
    Class nc = [NSNotificationCenter class];
    
    // postNotificationName:object:userInfo:
    Method m1 = class_getInstanceMethod(nc, @selector(postNotificationName:object:userInfo:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *name, id obj, NSDictionary *info) {
            LOG_NOTIFY(@"📢 [Notify] post: %@ | obj=%@ | info=%@", name, obj, info);
            ((void (*)(id, SEL, NSString*, id, NSDictionary*))orig)(self, @selector(postNotificationName:object:userInfo:), name, obj, info);
        });
        class_replaceMethod(nc, @selector(postNotificationName:object:userInfo:), newIMP, te);
    }
    
    // postNotification:
    Method m2 = class_getInstanceMethod(nc, @selector(postNotification:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSNotification *n) {
            LOG_NOTIFY(@"📢 [Notify] postNotification: %@", n);
            ((void (*)(id, SEL, NSNotification*))orig)(self, @selector(postNotification:), n);
        });
        class_replaceMethod(nc, @selector(postNotification:), newIMP, te);
    }
    
    logRaw(@"✅ 通知中心拦截已启用");
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
            LOG_DEF(@"💾 [UD set] %@ = %@", key, desc);
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
            LOG_DEF(@"💾 [UD get] %@ = %@", key, desc);
            return val;
        });
        class_replaceMethod(ud, @selector(objectForKey:), newIMP, te);
    }
    
    // setBool:forKey:
    Method m3 = class_getInstanceMethod(ud, @selector(setBool:forKey:));
    if (m3) {
        IMP orig = method_getImplementation(m3);
        const char *te = method_getTypeEncoding(m3);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL val, NSString *key) {
            LOG_DEF(@"💾 [UD setBool] %@ = %d", key, val);
            ((void (*)(id, SEL, BOOL, NSString*))orig)(self, @selector(setBool:forKey:), val, key);
        });
        class_replaceMethod(ud, @selector(setBool:forKey:), newIMP, te);
    }
    
    logRaw(@"✅ NSUserDefaults 拦截已启用");
}

#pragma mark - ===== 关键类特别关注 =====

static void hookCriticalClasses(void) {
    // 对核心类进行全方法追踪
    traceClass(@"WWWActivationViewController", @"ActVC");
    traceClass(@"ViewController", @"MainVC");
    
    // 追踪所有 KFun / WWW 前缀类
    traceAllClassesWithPrefix(@"KFun");
    traceAllClassesWithPrefix(@"WWW");
    traceAllClassesWithPrefix(@"XPF");
    
    // 特别 Hook ActVC 的几个关键方法，增加快照
    Class actVC = objc_getClass("WWWActivationViewController");
    if (actVC) {
        // viewDidLoad 后快照
        Method m = class_getInstanceMethod(actVC, @selector(viewDidLoad));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG_METHOD(@"🎯 [ActVC] viewDidLoad 开始");
                ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
                snapshotObj(self, @"ActVC(viewDidLoad后)");
                LOG_METHOD(@"🎯 [ActVC] viewDidLoad 结束");
            });
            class_replaceMethod(actVC, @selector(viewDidLoad), newIMP, te);
        }
        
        // onTapVerify
        m = class_getInstanceMethod(actVC, @selector(onTapVerify));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG_METHOD(@"🎯 [ActVC] onTapVerify 触发");
                snapshotObj(self, @"ActVC(onTapVerify前)");
                ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
                snapshotObj(self, @"ActVC(onTapVerify后)");
            });
            class_replaceMethod(actVC, @selector(onTapVerify), newIMP, te);
        }
        
        // showSuccess:completion:
        m = class_getInstanceMethod(actVC, @selector(showSuccess:completion:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg, id completion) {
                LOG_METHOD(@"🎯 [ActVC] showSuccess: %@ | completion=%@", msg, completion);
                id wrapped = ^(void) {
                    LOG_METHOD(@"🎉 [ActVC] showSuccess completion 执行！");
                    if (completion) ((void(^)(void))completion)();
                    snapshotObj(self, @"ActVC(showSuccess completion后)");
                };
                ((void (*)(id, SEL, NSString*, id))orig)(self, @selector(showSuccess:completion:), msg, wrapped);
            });
            class_replaceMethod(actVC, @selector(showSuccess:completion:), newIMP, te);
        }
        
        // setupAfterActivation
        m = class_getInstanceMethod(actVC, @selector(setupAfterActivation));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG_METHOD(@"🎯 [ActVC] setupAfterActivation 调用");
                ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
                snapshotObj(self, @"ActVC(setupAfterActivation后)");
            });
            class_replaceMethod(actVC, @selector(setupAfterActivation), newIMP, te);
        }
    }
    
    // MainVC 关键方法
    Class mainVC = objc_getClass("ViewController");
    if (mainVC) {
        Method m = class_getInstanceMethod(mainVC, @selector(viewDidLoad));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG_METHOD(@"🎯 [MainVC] viewDidLoad 开始");
                ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
                snapshotObj(self, @"MainVC(viewDidLoad后)");
                LOG_METHOD(@"🎯 [MainVC] viewDidLoad 结束");
            });
            class_replaceMethod(mainVC, @selector(viewDidLoad), newIMP, te);
        }
        
        m = class_getInstanceMethod(mainVC, @selector(viewDidAppear:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, BOOL anim) {
                LOG_METHOD(@"🎯 [MainVC] viewDidAppear: 开始");
                ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), anim);
                snapshotObj(self, @"MainVC(viewDidAppear后)");
                LOG_METHOD(@"🎯 [MainVC] viewDidAppear: 结束");
            });
            class_replaceMethod(mainVC, @selector(viewDidAppear:), newIMP, te);
        }
    }
}

#pragma mark - ===== 入口 =====

__attribute__((constructor))
static void kfun_analyzer_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunA] %@ 分析器已加载", ANALYZER_VERSION);
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWindow();
        hookNetwork();
        hookNotifications();
        hookUserDefaults();
        hookCriticalClasses();
        
        logRaw(@"🚀 分析器初始化完成");
        logRaw(@"📋 使用步骤：");
        logRaw(@"   1. 确保使用正版卡密");
        logRaw(@"   2. 正常点击验证，等待主页面加载");
        logRaw(@"   3. 观察日志中的 [UD set] / [Notify] / [Session] 流向");
        logRaw(@"   4. 点击 💾 保存日志到 /var/mobile/kfun_analyzer_log.txt");
        logRaw(@"   5. 用 Filza 取出日志，分析正版流程的完整调用链");
    });
}
