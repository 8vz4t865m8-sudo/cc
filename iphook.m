//
//  iphook.m - KFun 运行时探测版 v4
//  目标： pinpoint 主页面空白根因
//  约束：iOS 18.4 未越狱，轻松签注入，无文件写入权限
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

// ============================================================
// 日志系统（精简版，无重复轮询）
// ============================================================
static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunProbe] %@", line);
    
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 12000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 12000)];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = g_logBuffer;
            [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)];
        }
    });
}

// ============================================================
// 悬浮窗（修复复制按钮）
// ============================================================
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
        LOG(@"📋 日志已复制到剪贴板 (%lu 字符)", (unsigned long)g_logBuffer.length);
    } else {
        LOG(@"⚠️ 日志为空，无法复制");
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
        title.text = @"🔍 KFun 探测 (拖动标题栏)";
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
        LOG(@"✅ 探测悬浮窗已启动");
    });
}

// ============================================================
// 运行时方法枚举器
// ============================================================
static void dumpClassMethods(Class cls, NSString *label) {
    if (!cls) { LOG(@"❌ %@ 类不存在", label); return; }
    LOG(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    LOG(@"📦 %@ 类名: %@", label, NSStringFromClass(cls));
    
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    LOG(@"   实例方法数: %u", count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *typeEnc = method_getTypeEncoding(methods[i]);
        LOG(@"   [%u] %s  |  编码: %s", i, sel_getName(sel), typeEnc ? typeEnc : "nil");
    }
    if (methods) free(methods);
    
    unsigned int propCount = 0;
    objc_property_t *props = class_copyPropertyList(cls, &propCount);
    LOG(@"   属性数: %u", propCount);
    for (unsigned int i = 0; i < propCount; i++) {
        const char *name = property_getName(props[i]);
        const char *attr = property_getAttributes(props[i]);
        LOG(@"   [%u] %s  |  attr: %s", i, name, attr ? attr : "nil");
    }
    if (props) free(props);
    
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    LOG(@"   实例变量数: %u", ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++) {
        const char *name = ivar_getName(ivars[i]);
        const char *type = ivar_getTypeEncoding(ivars[i]);
        LOG(@"   [%u] %s  |  type: %s", i, name, type ? type : "nil");
    }
    if (ivars) free(ivars);
    LOG(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

// ============================================================
// 通用方法拦截器（记录调用，不打断流程）
// ============================================================
static void hookAllMethodsOfClass(Class cls, NSString *label) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *selName = NSStringFromSelector(sel);
        
        // 跳过系统方法和已知高频方法（避免日志爆炸）
        if ([selName hasPrefix:@"_"] || [selName isEqualToString:@"dealloc"] ||
            [selName isEqualToString:@"description"] || [selName isEqualToString:@"debugDescription"] ||
            [selName isEqualToString:@"hash"] || [selName isEqualToString:@"isEqual:"]) continue;
        
        IMP origIMP = method_getImplementation(methods[i]);
        method_setImplementation(methods[i], imp_implementationWithBlock(^(id self, ...) {
            LOG(@"🎣 [%@] %@ 被调用", label, selName);
            // 调用原方法（使用 objc_msgSend 转发，保持所有参数）
            return ((id (*)(id, SEL))origIMP)(self, sel);
        }));
    }
    if (methods) free(methods);
    LOG(@"✅ %@ 已 hook %u 个方法", label, count);
}

// ============================================================
// 属性快照探测器
// ============================================================
static void snapshotProperties(id obj, NSString *label) {
    if (!obj) { LOG(@"❌ %@ 对象 nil", label); return; }
    LOG(@"📸 [%@] 属性快照 begin", label);
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            id val = [obj valueForKey:name];
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 100) desc = [desc substringToIndex:100];
            LOG(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {
            LOG(@"   %@ = [读取失败: %@]", name, e.reason);
        }
    }
    if (props) free(props);
    LOG(@"📸 [%@] 属性快照 end", label);
}

// ============================================================
// 网络请求拦截
// ============================================================
static void hookNSURLSession() {
    Class cls = [NSURLSession class];
    Method m = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (!m) { LOG(@"⚠️ 未找到 dataTaskWithURL:completionHandler:"); return; }
    
    IMP orig = method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^(id self, NSURL *url, id completion) {
        LOG(@"🌐 [NSURLSession] 请求: %@", url.absoluteString);
        id wrappedCompletion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
            LOG(@"🌐 [NSURLSession] 响应: %@ | 状态码: %ld | 错误: %@",
                url.absoluteString, (long)(http ? http.statusCode : 0), error ? error.localizedDescription : @"无");
            if (data && data.length < 2000) {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (body) LOG(@"🌐 [NSURLSession] Body: %@", body);
            }
            if (completion) ((void(^)(NSData*, NSURLResponse*, NSError*))completion)(data, response, error);
        };
        return ((id (*)(id, SEL, NSURL*, id))orig)(self, @selector(dataTaskWithURL:completionHandler:), url, wrappedCompletion);
    }));
    LOG(@"✅ NSURLSession 网络拦截已启用");
}

// ============================================================
// v3 Bypass 核心（保留）
// ============================================================
static void doBypass(id vcInstance) {
    LOG(@"🚀 Bypass 触发");
    
    @try {
        id spinner = [vcInstance valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
            LOG(@"✅ spinner 已停止");
        }
    } @catch (NSException *e) {}
    
    @try {
        if ([vcInstance respondsToSelector:@selector(setLoading:)]) {
            [vcInstance performSelector:@selector(setLoading:) withObject:@NO];
        }
    } @catch (NSException *e) {}
    
    @try {
        id mask = [vcInstance valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            LOG(@"✅ authMaskView 已移除");
        }
    } @catch (NSException *e) {}
    
    @try {
        id errorLabel = [vcInstance valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
    } @catch (NSException *e) {}
    
    @try {
        if ([vcInstance respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            [vcInstance performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
            LOG(@"✅ buildSuccessViewWithExpire: 已调用");
        }
    } @catch (NSException *e) { LOG(@"❌ buildSuccessViewWithExpire: %@", e.reason); }
    
    @try {
        if ([vcInstance respondsToSelector:@selector(setupAfterActivation)]) {
            [vcInstance performSelector:@selector(setupAfterActivation)];
            LOG(@"✅ setupAfterActivation 已调用");
        } else {
            LOG(@"⚠️ 无 setupAfterActivation");
        }
    } @catch (NSException *e) { LOG(@"❌ setupAfterActivation: %@", e.reason); }
    
    // 探测：调用 bypass 后的属性快照
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        snapshotProperties(vcInstance, @"WWWActivationViewController(bypass后)");
    });
    
    // 延迟关闭
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([vcInstance isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)vcInstance;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:nil];
                    LOG(@"✅ dismiss 验证弹窗");
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// Hook 入口
// ============================================================
static void hookVCClass(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
    LOG(@"🎣 Hook VC: %s", class_getName(cls));
    
    Method m;
    
    // viewDidLoad — 自动 bypass + 枚举方法
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [WWWActivationViewController] viewDidLoad");
            struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&super, @selector(viewDidLoad));
            
            // 首次加载时枚举方法
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                dumpClassMethods([self class], @"WWWActivationViewController");
                dumpClassMethods(objc_getClass("WWWActivation"), @"WWWActivation");
                dumpClassMethods(objc_getClass("ViewController"), @"ViewController");
            });
            
            // 属性快照
            snapshotProperties(self, @"WWWActivationViewController(viewDidLoad)");
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                doBypass(self);
            });
        }));
        LOG(@"  ✅ viewDidLoad");
    }
    
    // onTapVerify — 点击 bypass
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [WWWActivationViewController] onTapVerify 被拦截");
            doBypass(self);
        }));
        LOG(@"  ✅ onTapVerify");
    } else {
        LOG(@"  ⚠️ 无 onTapVerify");
    }
    
    // showError: — 拦截错误
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *msg) {
            LOG(@"🛡️ [WWWActivationViewController] showError: %@", msg);
            doBypass(self);
        }));
        LOG(@"  ✅ showError:");
    }
    
    // isActivated → YES
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            return YES;
        }));
        LOG(@"  ✅ isActivated -> YES");
    }
    
    // isVerified → YES
    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            return YES;
        }));
        LOG(@"  ✅ isVerified -> YES");
    }
    
    // 关键：拦截 showSuccess:completion: 看 completion 签名
    m = class_getInstanceMethod(cls, @selector(showSuccess:completion:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id expire, id completion) {
            LOG(@"🎯 [WWWActivationViewController] showSuccess:completion: 被调用");
            LOG(@"   expire参数: %@", expire);
            LOG(@"   completion类型: %@", NSStringFromClass([completion class]));
            
            // 尝试执行 completion（如果它是 block）
            if (completion) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    @try {
                        // 尝试无参调用
                        typedef void (^VoidBlock)(void);
                        VoidBlock blk = (VoidBlock)completion;
                        blk();
                        LOG(@"✅ completion block 已执行(无参)");
                    } @catch (NSException *e) {
                        LOG(@"❌ completion block 调用失败: %@", e.reason);
                    }
                });
            }
            
            // 同时调用 setupAfterActivation
            if ([self respondsToSelector:@selector(setupAfterActivation)]) {
                [self performSelector:@selector(setupAfterActivation)];
            }
        }));
        LOG(@"  ✅ showSuccess:completion:");
    } else {
        LOG(@"  ⚠️ 无 showSuccess:completion:");
    }
    
    // 拦截 verifyWithCompletion:
    m = class_getInstanceMethod(cls, @selector(verifyWithCompletion:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id completion) {
            LOG(@"🎯 [WWWActivationViewController] verifyWithCompletion: 被调用");
            LOG(@"   completion类型: %@", NSStringFromClass([completion class]));
            if (completion) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    @try {
                        typedef void (^VoidBlock)(void);
                        VoidBlock blk = (VoidBlock)completion;
                        blk();
                        LOG(@"✅ verify completion 已执行(无参)");
                    } @catch (NSException *e) {
                        LOG(@"❌ verify completion 调用失败: %@", e.reason);
                    }
                });
            }
        }));
        LOG(@"  ✅ verifyWithCompletion:");
    } else {
        LOG(@"  ⚠️ 无 verifyWithCompletion:");
    }
    
    // 通用方法拦截（记录所有方法调用）
    hookAllMethodsOfClass(cls, @"WWWActivationViewController");
}

static void hookViewController(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 ViewController"); return; }
    LOG(@"🎣 Hook ViewController: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [ViewController] viewDidLoad");
            struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&super, @selector(viewDidLoad));
            snapshotProperties(self, @"ViewController(viewDidLoad)");
        }));
        LOG(@"  ✅ ViewController viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewWillAppear:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [ViewController] viewWillAppear:");
            struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
            ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&super, @selector(viewWillAppear:), animated);
            snapshotProperties(self, @"ViewController(viewWillAppear)");
        }));
        LOG(@"  ✅ ViewController viewWillAppear:");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [ViewController] viewDidAppear:");
            struct objc_super super = {self, class_getSuperclass(object_getClass(self))};
            ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&super, @selector(viewDidAppear:), animated);
            snapshotProperties(self, @"ViewController(viewDidAppear)");
        }));
        LOG(@"  ✅ ViewController viewDidAppear:");
    }
    
    // 通用拦截
    hookAllMethodsOfClass(cls, @"ViewController");
}

// ============================================================
// 初始化
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunProbe] 探测版 v4 已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        
        // 网络拦截
        hookNSURLSession();
        
        // Hook 验证页
        Class vcClass = objc_getClass("WWWActivationViewController");
        if (vcClass) hookVCClass(vcClass);
        
        // Hook 主页
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        
        LOG(@"🚀 探测系统初始化完成");
        LOG(@"📋 操作说明：");
        LOG(@"   1. 正常打开软件，等自动 bypass 进主页面");
        LOG(@"   2. 观察悬浮窗日志");
        LOG(@"   3. 点击【复制】按钮，粘贴发给我");
    });
}
