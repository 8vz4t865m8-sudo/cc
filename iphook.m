//
//  iphook.m - KFun 真卡密记录版 v3-fix2 (闪退修复2)
//  核心修复：activateCode:completion: 不再 wrap completion block
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;
static __weak id g_wwwActivation = nil;  // 保存 WWWActivation 实例用于延迟快照

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunRecV3] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 60000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 60000)];
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
        title.text = @"🔍 KFun v3-fix2 (拖动)";
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
// 通用工具
// ============================================================
static void snapshotProperties(id obj, NSString *label) {
    if (!obj) { LOG(@"❌ %@ nil", label); return; }
    LOG(@"📸 [%@] begin", label);
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            id val = [obj valueForKey:name];
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 120) desc = [desc substringToIndex:120];
            LOG(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {
            LOG(@"   %@ = [err:%@]", name, e.reason);
        }
    }
    if (props) free(props);
    LOG(@"📸 [%@] end", label);
}

static void snapshotIvars(id obj, NSString *label) {
    if (!obj) { LOG(@"❌ %@ nil", label); return; }
    LOG(@"📦 [%@] ivars begin", label);
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i])];
        @try {
            id val = object_getIvar(obj, ivars[i]);
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 120) desc = [desc substringToIndex:120];
            LOG(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {
            LOG(@"   %@ = [err:%@]", name, e.reason);
        }
    }
    if (ivars) free(ivars);
    LOG(@"📦 [%@] ivars end", label);
}

static void dumpViewHierarchy(UIView *view, NSString *label, int depth) {
    if (!view) return;
    if (depth > 6) return;
    NSString *indent = [@"" stringByPaddingToLength:depth*2 withString:@"  " startingAtIndex:0];
    NSString *hidden = view.hidden ? @"[H]" : @"";
    NSString *frame = NSStringFromCGRect(view.frame);
    LOG(@"%@[V]%@ %@ frame=%@ alpha=%.1f", indent, hidden, NSStringFromClass([view class]), frame, view.alpha);
    for (UIView *sub in view.subviews) {
        dumpViewHierarchy(sub, label, depth + 1);
    }
}

static void dumpAllWindows(NSString *label) {
    LOG(@"🪟 [%@] 所有窗口 begin", label);
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *w in windows) {
        LOG(@"  Window %@ | root=%@ | hidden=%d", NSStringFromClass([w class]), NSStringFromClass([w.rootViewController class]), (int)w.hidden);
        if (w.rootViewController) {
            dumpViewHierarchy(w.rootViewController.view, label, 1);
        }
    }
    LOG(@"🪟 [%@] 所有窗口 end", label);
}

// ============================================================
// 🔔 NSNotificationCenter 监控 (过滤系统通知)
// ============================================================
static IMP g_origPostNotification2 = NULL;

static void hookNSNotificationCenter() {
    Class cls = objc_getClass("NSNotificationCenter");
    if (!cls) return;
    
    Method m2 = class_getInstanceMethod(cls, @selector(postNotificationName:object:userInfo:));
    if (m2) {
        g_origPostNotification2 = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP imp = imp_implementationWithBlock(^(id self, NSString *name, id obj, NSDictionary *ui) {
            BOOL isSystem = NO;
            NSArray *sysPrefixes = @[@\"UI\", @\"NS\", @\"_UI\", @\"AX\", @\"kCA\", @\"CADisplay\", @\"UIApplication\", @\"UIWindow\", @\"UIText\", @\"UIKeyboard\", @\"UIScroll\", @\"UITable\", @\"UICollection\", @\"UIFocus\", @\"UITrait\", @\"UIViewController\", @\"UIScene\", @\"UIStatusBar\", @\"UINavigation\", @\"UITabBar\", @\"UIAlert\", @\"UIAction\", @\"UIPresentation\", @\"UIDevice\", @\"UIScreen\", @\"UIDisplay\"];
            for (NSString *p in sysPrefixes) {
                if ([name hasPrefix:p]) { isSystem = YES; break; }
            }
            if (!isSystem) {
                NSString *objStr = obj ? [NSString stringWithFormat:@"%@", obj] : @"nil";
                NSString *uiStr = ui ? [NSString stringWithFormat:@"%@", ui] : @"nil";
                if (objStr.length > 200) objStr = [objStr substringToIndex:200];
                if (uiStr.length > 500) uiStr = [uiStr substringToIndex:500];
                LOG(@"🔔 postNotification: name=%@ obj=%@ userInfo=%@", name, objStr, uiStr);
            }
            ((void (*)(id, SEL, NSString*, id, NSDictionary*))g_origPostNotification2)(self, @selector(postNotificationName:object:userInfo:), name, obj, ui);
        });
        class_replaceMethod(cls, @selector(postNotificationName:object:userInfo:), imp, te);
    }
    
    Method m3 = class_getInstanceMethod(cls, @selector(addObserver:selector:name:object:));
    if (m3) {
        IMP orig = method_getImplementation(m3);
        const char *te = method_getTypeEncoding(m3);
        IMP imp = imp_implementationWithBlock(^(id self, id observer, SEL sel, NSString *name, id obj) {
            BOOL isSystem = NO;
            NSArray *sysPrefixes = @[@\"UI\", @\"NS\", @\"_UI\", @\"AX\", @\"kCA\", @\"CADisplay\", @\"UIApplication\", @\"UIWindow\", @\"UIText\", @\"UIKeyboard\", @\"UIScroll\", @\"UITable\", @\"UICollection\", @\"UIFocus\", @\"UITrait\", @\"UIViewController\", @\"UIScene\", @\"UIStatusBar\", @\"UINavigation\", @\"UITabBar\", @\"UIAlert\", @\"UIAction\", @\"UIPresentation\", @\"UIDevice\", @\"UIScreen\", @\"UIDisplay\"];
            for (NSString *p in sysPrefixes) {
                if ([name hasPrefix:p]) { isSystem = YES; break; }
            }
            if (!isSystem) {
                LOG(@"👂 addObserver: observer=%@ selector=%@ name=%@", NSStringFromClass([observer class]), NSStringFromSelector(sel), name);
            }
            ((void (*)(id, SEL, id, SEL, NSString*, id))orig)(self, @selector(addObserver:selector:name:object:), observer, sel, name, obj);
        });
        class_replaceMethod(cls, @selector(addObserver:selector:name:object:), imp, te);
    }
    
    LOG(@"✅ NSNotificationCenter 已 Hook");
}

// ============================================================
// 💾 NSUserDefaults 监控
// ============================================================
static void hookNSUserDefaults() {
    Class cls = [NSUserDefaults class];
    
    Method m1 = class_getInstanceMethod(cls, @selector(setObject:forKey:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP imp = imp_implementationWithBlock(^(id self, id val, NSString *key) {
            NSString *v = val ? [NSString stringWithFormat:@"%@", val] : @"nil";
            if (v.length > 300) v = [v substringToIndex:300];
            LOG(@"💾 NSUserDefaults setObject: key=%@ value=%@", key, v);
            ((void (*)(id, SEL, id, NSString*))orig)(self, @selector(setObject:forKey:), val, key);
        });
        class_replaceMethod(cls, @selector(setObject:forKey:), imp, te);
    }
    
    Method m2 = class_getInstanceMethod(cls, @selector(setBool:forKey:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP imp = imp_implementationWithBlock(^(id self, BOOL val, NSString *key) {
            LOG(@"💾 NSUserDefaults setBool: key=%@ value=%d", key, (int)val);
            ((void (*)(id, SEL, BOOL, NSString*))orig)(self, @selector(setBool:forKey:), val, key);
        });
        class_replaceMethod(cls, @selector(setBool:forKey:), imp, te);
    }
    
    Method m3 = class_getInstanceMethod(cls, @selector(setInteger:forKey:));
    if (m3) {
        IMP orig = method_getImplementation(m3);
        const char *te = method_getTypeEncoding(m3);
        IMP imp = imp_implementationWithBlock(^(id self, NSInteger val, NSString *key) {
            LOG(@"💾 NSUserDefaults setInteger: key=%@ value=%ld", key, (long)val);
            ((void (*)(id, SEL, NSInteger, NSString*))orig)(self, @selector(setInteger:forKey:), val, key);
        });
        class_replaceMethod(cls, @selector(setInteger:forKey:), imp, te);
    }
    
    LOG(@"✅ NSUserDefaults 已 Hook");
}

// ============================================================
// 🌐 网络监控 (URL + Request)
// ============================================================
static void recordNetwork() {
    Class cls = [NSURLSession class];
    
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        const char *te = method_getTypeEncoding(m1);
        IMP imp = imp_implementationWithBlock(^(id self, NSURL *url, id completion) {
            LOG(@"🌐 [URL] %@", url.absoluteString);
            id wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
                LOG(@"🌐 [URL响应] %@ | %ld | %@", url.absoluteString, (long)(http?http.statusCode:0), error?error.localizedDescription:@"ok");
                if (data && data.length < 3000) {
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (body) LOG(@"🌐 [URLBody] %@", body);
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, response, error);
            };
            return ((id (*)(id, SEL, NSURL*, id))orig)(self, @selector(dataTaskWithURL:completionHandler:), url, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithURL:completionHandler:), imp, te);
    }
    
    Method m2 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        const char *te = method_getTypeEncoding(m2);
        IMP imp = imp_implementationWithBlock(^(id self, NSURLRequest *req, id completion) {
            NSString *body = nil;
            if (req.HTTPBody && req.HTTPBody.length < 3000) {
                body = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
            }
            NSString *headers = req.allHTTPHeaderFields ? [NSString stringWithFormat:@"%@", req.allHTTPHeaderFields] : @"nil";
            if (headers.length > 300) headers = [headers substringToIndex:300];
            LOG(@"🌐 [REQ] %@ | method=%@ | body=%@ | headers=%@", req.URL.absoluteString, req.HTTPMethod, body?body:@"nil", headers);
            
            id wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
                LOG(@"🌐 [REQ响应] %@ | %ld | %@", req.URL.absoluteString, (long)(http?http.statusCode:0), error?error.localizedDescription:@"ok");
                if (data && data.length < 3000) {
                    NSString *rbody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (rbody) LOG(@"🌐 [REQBody] %@", rbody);
                }
                if (completion) ((void(^)(NSData*,NSURLResponse*,NSError*))completion)(data, response, error);
            };
            return ((id (*)(id, SEL, NSURLRequest*, id))orig)(self, @selector(dataTaskWithRequest:completionHandler:), req, wrapped);
        });
        class_replaceMethod(cls, @selector(dataTaskWithRequest:completionHandler:), imp, te);
    }
    
    LOG(@"✅ 网络记录已启用");
}

// ============================================================
// 🎣 WWWActivation 类监控 (修复：不再 wrap completion block)
// ============================================================
static void hookWWWActivation(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 WWWActivation"); return; }
    LOG(@"🎣 Hook WWWActivation: %s", class_getName(cls));
    
    Method m;
    
    // ⭐ 修复：不再替换 completion block，直接调用原始方法
    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, NSString *code, id completion) {
            LOG(@"🎣 [WWWActivation] activateCode: %@", code);
            if (completion) {
                LOG(@"🎣   completion class = %@", NSStringFromClass([completion class]));
            }
            g_wwwActivation = self;
            // 调用前快照
            snapshotProperties(self, @"WWWActivation(activateCode调用前)");
            
            id ret = ((id (*)(id, SEL, NSString*, id))orig)(self, @selector(activateCode:completion:), code, completion);
            
            LOG(@"🎣 [WWWActivation] activateCode 已调用，返回=%@", ret ? [NSString stringWithFormat:@"%@", ret] : @"nil");
            
            // 延迟快照：0.5s / 1s / 2s / 3s 后检查属性变化
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (g_wwwActivation) snapshotProperties(g_wwwActivation, @"WWWActivation(activateCode+0.5s)");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (g_wwwActivation) snapshotProperties(g_wwwActivation, @"WWWActivation(activateCode+1.0s)");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (g_wwwActivation) snapshotProperties(g_wwwActivation, @"WWWActivation(activateCode+2.0s)");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (g_wwwActivation) snapshotProperties(g_wwwActivation, @"WWWActivation(activateCode+3.0s)");
            });
            
            return ret;
        });
        class_replaceMethod(cls, @selector(activateCode:completion:), imp, te);
        LOG(@"  ✅ activateCode:completion:");
    }
    
    // ⭐ 修复：同样不 wrap completion
    m = class_getInstanceMethod(cls, @selector(verifyWithCompletion:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, id completion) {
            LOG(@"🎣 [WWWActivation] verifyWithCompletion:");
            g_wwwActivation = self;
            snapshotProperties(self, @"WWWActivation(verify调用前)");
            id ret = ((id (*)(id, SEL, id))orig)(self, @selector(verifyWithCompletion:), completion);
            LOG(@"🎣 [WWWActivation] verifyWithCompletion 已调用");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (g_wwwActivation) snapshotProperties(g_wwwActivation, @"WWWActivation(verify+1.0s)");
            });
            return ret;
        });
        class_replaceMethod(cls, @selector(verifyWithCompletion:), imp, te);
        LOG(@"  ✅ verifyWithCompletion:");
    }
    
    m = class_getInstanceMethod(cls, @selector(setupAfterActivation));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self) {
            LOG(@"🎣 [WWWActivation] setupAfterActivation 被调用");
            snapshotProperties(self, @"WWWActivation(setupAfterActivation前)");
            ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
            snapshotProperties(self, @"WWWActivation(setupAfterActivation后)");
        });
        class_replaceMethod(cls, @selector(setupAfterActivation), imp, te);
        LOG(@"  ✅ setupAfterActivation");
    }
    
    m = class_getInstanceMethod(cls, @selector(activationStampPath));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self) {
            NSString *path = ((NSString* (*)(id, SEL))orig)(self, @selector(activationStampPath));
            LOG(@"🎣 [WWWActivation] activationStampPath = %@", path);
            return path;
        });
        class_replaceMethod(cls, @selector(activationStampPath), imp, te);
        LOG(@"  ✅ activationStampPath");
    }
    
    // Hook 所有 setter（只限本类）
    unsigned int mc = 0;
    Method *methods = class_copyMethodList(cls, &mc);
    for (unsigned int i = 0; i < mc; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        if ([name hasPrefix:@"set"] && [name hasSuffix:@":"]) {
            const char *te = method_getTypeEncoding(methods[i]);
            IMP orig = method_getImplementation(methods[i]);
            IMP imp = imp_implementationWithBlock(^(id self, id val) {
                NSString *v = val ? [NSString stringWithFormat:@"%@", val] : @"nil";
                if (v.length > 200) v = [v substringToIndex:200];
                LOG(@"🎣 [WWWActivation] %@ = %@", name, v);
                ((void (*)(id, SEL, id))orig)(self, sel, val);
            });
            class_replaceMethod(cls, sel, imp, te);
        }
    }
    if (methods) free(methods);
    LOG(@"  ✅ 所有 setter 已 Hook");
}

// ============================================================
// 🎣 WWWActivationViewController 监控
// ============================================================
static __weak id g_actVC = nil;

static void hookActivationVC(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
    LOG(@"🎣 Hook ActVC: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [ActVC] viewDidLoad");
            g_actVC = self;
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
            snapshotProperties(self, @"ActVC(viewDidLoad)");
            snapshotIvars(self, @"ActVC(viewDidLoad)");
        });
        class_replaceMethod(cls, @selector(viewDidLoad), imp, te);
        LOG(@"  ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [ActVC] onTapVerify 被点击");
            snapshotProperties(self, @"ActVC(点击验证前)");
            ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
            LOG(@"🎯 [ActVC] onTapVerify 执行完毕");
            snapshotProperties(self, @"ActVC(点击验证后)");
        });
        class_replaceMethod(cls, @selector(onTapVerify), imp, te);
        LOG(@"  ✅ onTapVerify");
    }
    
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, NSString *msg) {
            LOG(@"🛡️ [ActVC] showError: %@", msg);
            snapshotProperties(self, @"ActVC(showError)");
            ((void (*)(id, SEL, NSString*))orig)(self, @selector(showError:), msg);
        });
        class_replaceMethod(cls, @selector(showError:), imp, te);
        LOG(@"  ✅ showError:");
    }
    
    m = class_getInstanceMethod(cls, @selector(showSuccess:completion:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, id expire, id completion) {
            LOG(@"🎉 [ActVC] showSuccess:completion: 被调用");
            LOG(@"   expire = %@", expire);
            LOG(@"   completion class = %@", completion ? NSStringFromClass([completion class]) : @"nil");
            snapshotProperties(self, @"ActVC(showSuccess前)");
            snapshotIvars(self, @"ActVC(showSuccess前)");
            
            id wrapped = ^(void) {
                LOG(@"🎉 [ActVC] showSuccess completion block 执行！");
                if (completion) ((void(^)(void))completion)();
            };
            
            ((void (*)(id, SEL, id, id))orig)(self, @selector(showSuccess:completion:), expire, wrapped);
            LOG(@"🎉 [ActVC] showSuccess:completion: 执行完毕");
            snapshotProperties(self, @"ActVC(showSuccess后)");
            snapshotIvars(self, @"ActVC(showSuccess后)");
        });
        class_replaceMethod(cls, @selector(showSuccess:completion:), imp, te);
        LOG(@"  ✅ showSuccess:completion:");
    }
    
    m = class_getInstanceMethod(cls, @selector(buildSuccessViewWithExpire:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, id expire) {
            LOG(@"🎉 [ActVC] buildSuccessViewWithExpire: %@", expire);
            snapshotProperties(self, @"ActVC(buildSuccessView前)");
            ((void (*)(id, SEL, id))orig)(self, @selector(buildSuccessViewWithExpire:), expire);
            snapshotProperties(self, @"ActVC(buildSuccessView后)");
        });
        class_replaceMethod(cls, @selector(buildSuccessViewWithExpire:), imp, te);
        LOG(@"  ✅ buildSuccessViewWithExpire:");
    }
    
    m = class_getInstanceMethod(cls, @selector(setupAfterActivation));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self) {
            LOG(@"🎉 [ActVC] setupAfterActivation 被调用");
            snapshotProperties(self, @"ActVC(setupAfterActivation前)");
            ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
            snapshotProperties(self, @"ActVC(setupAfterActivation后)");
        });
        class_replaceMethod(cls, @selector(setupAfterActivation), imp, te);
        LOG(@"  ✅ setupAfterActivation");
    }
    
    m = class_getInstanceMethod(cls, @selector(setOnVerify:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, id block) {
            LOG(@"🔔 [ActVC] setOnVerify: %@", block ? @"非nil block" : @"nil");
            ((void (*)(id, SEL, id))orig)(self, @selector(setOnVerify:), block);
        });
        class_replaceMethod(cls, @selector(setOnVerify:), imp, te);
        LOG(@"  ✅ setOnVerify:");
    }
    
    m = class_getInstanceMethod(cls, @selector(dismissViewControllerAnimated:completion:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, BOOL anim, id completion) {
            LOG(@"🚪 [ActVC] dismissViewControllerAnimated:%d", (int)anim);
            dumpAllWindows(@"ActVC dismiss前");
            id wrapped = ^(void) {
                LOG(@"🚪 [ActVC] dismiss completion");
                dumpAllWindows(@"ActVC dismiss后");
                if (completion) ((void(^)(void))completion)();
            };
            ((void (*)(id, SEL, BOOL, id))orig)(self, @selector(dismissViewControllerAnimated:completion:), anim, wrapped);
        });
        class_replaceMethod(cls, @selector(dismissViewControllerAnimated:completion:), imp, te);
        LOG(@"  ✅ dismissViewControllerAnimated:completion:");
    }
}

// ============================================================
// 🎣 MainVC (ViewController) 监控
// ============================================================
static void hookViewController(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 ViewController"); return; }
    LOG(@"🎣 Hook MainVC: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [MainVC] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
            snapshotProperties(self, @"MainVC(viewDidLoad)");
            snapshotIvars(self, @"MainVC(viewDidLoad)");
            dumpViewHierarchy(((UIViewController*)self).view, @"MainVC(viewDidLoad)", 0);
        });
        class_replaceMethod(cls, @selector(viewDidLoad), imp, te);
        LOG(@"  ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewWillAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [MainVC] viewWillAppear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewWillAppear:), animated);
            snapshotProperties(self, @"MainVC(viewWillAppear)");
        });
        class_replaceMethod(cls, @selector(viewWillAppear:), imp, te);
        LOG(@"  ✅ viewWillAppear:");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [MainVC] viewDidAppear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
            snapshotProperties(self, @"MainVC(viewDidAppear)");
            snapshotIvars(self, @"MainVC(viewDidAppear)");
            dumpViewHierarchy(((UIViewController*)self).view, @"MainVC(viewDidAppear)", 0);
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                LOG(@"🎯 [MainVC] viewDidAppear + 0.05s");
                dumpViewHierarchy(((UIViewController*)self).view, @"MainVC(+0.05s)", 0);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                LOG(@"🎯 [MainVC] viewDidAppear + 0.1s");
                dumpViewHierarchy(((UIViewController*)self).view, @"MainVC(+0.1s)", 0);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                LOG(@"🎯 [MainVC] viewDidAppear + 0.2s");
                dumpViewHierarchy(((UIViewController*)self).view, @"MainVC(+0.2s)", 0);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                LOG(@"🎯 [MainVC] viewDidAppear + 0.5s");
                dumpViewHierarchy(((UIViewController*)self).view, @"MainVC(+0.5s)", 0);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                LOG(@"🎯 [MainVC] viewDidAppear + 1.0s");
                dumpViewHierarchy(((UIViewController*)self).view, @"MainVC(+1.0s)", 0);
            });
        });
        class_replaceMethod(cls, @selector(viewDidAppear:), imp, te);
        LOG(@"  ✅ viewDidAppear:");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewWillDisappear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [MainVC] viewWillDisappear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewWillDisappear:), animated);
        });
        class_replaceMethod(cls, @selector(viewWillDisappear:), imp, te);
        LOG(@"  ✅ viewWillDisappear:");
    }
    
    // Hook 所有 setter（只限本类）
    unsigned int mc = 0;
    Method *methods = class_copyMethodList(cls, &mc);
    for (unsigned int i = 0; i < mc; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        if ([name hasPrefix:@"set"] && [name hasSuffix:@":"]) {
            const char *te = method_getTypeEncoding(methods[i]);
            IMP orig = method_getImplementation(methods[i]);
            IMP imp = imp_implementationWithBlock(^(id self, id val) {
                NSString *v = val ? [NSString stringWithFormat:@"%@", val] : @"nil";
                if (v.length > 200) v = [v substringToIndex:200];
                LOG(@"🎯 [MainVC] %@ = %@", name, v);
                ((void (*)(id, SEL, id))orig)(self, sel, val);
            });
            class_replaceMethod(cls, sel, imp, te);
        }
    }
    if (methods) free(methods);
    LOG(@"  ✅ MainVC 所有 setter 已 Hook");
}

// ============================================================
// 🎣 AppDelegate 监控
// ============================================================
static void hookAppDelegate() {
    Class cls = objc_getClass("AppDelegate");
    if (!cls) {
        id delegate = [UIApplication sharedApplication].delegate;
        if (delegate) cls = [delegate class];
    }
    if (!cls) { LOG(@"⚠️ 未找到 AppDelegate"); return; }
    LOG(@"🎣 Hook AppDelegate: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(application:didFinishLaunchingWithOptions:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self, id app, id opts) {
            LOG(@"🚀 [AppDelegate] didFinishLaunchingWithOptions");
            BOOL ret = ((BOOL (*)(id, SEL, id, id))orig)(self, @selector(application:didFinishLaunchingWithOptions:), app, opts);
            snapshotProperties(self, @"AppDelegate(didFinishLaunching)");
            dumpAllWindows(@"AppDelegate启动后");
            return ret;
        });
        class_replaceMethod(cls, @selector(application:didFinishLaunchingWithOptions:), imp, te);
        LOG(@"  ✅ didFinishLaunchingWithOptions");
    }
    
    m = class_getInstanceMethod(cls, @selector(applicationDidBecomeActive:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        IMP imp = imp_implementationWithBlock(^(id self) {
            LOG(@"🚀 [AppDelegate] applicationDidBecomeActive");
            ((void (*)(id, SEL))orig)(self, @selector(applicationDidBecomeActive:));
            snapshotProperties(self, @"AppDelegate(becomeActive)");
        });
        class_replaceMethod(cls, @selector(applicationDidBecomeActive:), imp, te);
        LOG(@"  ✅ applicationDidBecomeActive");
    }
}

// ============================================================
// 初始化
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunRecV3] 真卡密增强记录版 v3-fix2 已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        hookNSNotificationCenter();
        hookNSUserDefaults();
        recordNetwork();
        hookAppDelegate();
        
        Class actCls = objc_getClass("WWWActivation");
        if (actCls) hookWWWActivation(actCls);
        
        Class vcClass = objc_getClass("WWWActivationViewController");
        if (vcClass) hookActivationVC(vcClass);
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        
        LOG(@"🚀 增强记录系统已启动");
        LOG(@"📋 操作：输入真卡密 → 点验证 → 等主页面内容出现 → 点复制发给我");
    });
}
