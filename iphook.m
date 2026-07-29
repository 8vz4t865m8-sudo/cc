//
//  iphook.m - KFun Bypass v14 (state修复版 + 显式刷新)
//  基于 v13，增加 MainVC.state 设置和数据加载触发，并强制调用 setup/reloadData
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
    NSLog(@"[KFunV14] %@", line);
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
        title.text = @"🔍 KFun v14 state修复 (拖动)";
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
        LOG(@"✅ 悬浮窗已启动 v14");
    });
}

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
            if (desc.length > 100) desc = [desc substringToIndex:100];
            LOG(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {
            LOG(@"   %@ = [err:%@]", name, e.reason);
        }
    }
    if (props) free(props);
    LOG(@"📸 [%@] end", label);
}

// ============================================================
// 🚀 Bypass 核心 - v14 修复版 + 显式刷新
// ============================================================
static void doBypass(id vcInstance) {
    LOG(@"🚀 Bypass v14 开始");
    
    // 1. 停止 spinner
    @try {
        id spinner = [vcInstance valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
            LOG(@"✅ spinner 停止");
        }
    } @catch (NSException *e) {}
    
    // 2. 隐藏错误提示
    @try {
        id errorLabel = [vcInstance valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
    } @catch (NSException *e) {}
    
    // 3. 移除遮罩
    @try {
        id mask = [vcInstance valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            LOG(@"✅ authMaskView 移除");
        }
    } @catch (NSException *e) {}
    
    // 4. 调用 showSuccess:completion:
    @try {
        if ([vcInstance respondsToSelector:@selector(showSuccess:completion:)]) {
            LOG(@"⭐ 调用 showSuccess:completion:...");
            __weak id weakVC = vcInstance;
            id completionBlock = ^(void) {
                LOG(@"🎉 completion block 执行！");
                __strong id strongVC = weakVC;
                if (strongVC) {
                    if ([strongVC respondsToSelector:@selector(setupAfterActivation)]) {
                        [strongVC performSelector:@selector(setupAfterActivation)];
                        LOG(@"✅ setupAfterActivation 已调用");
                    }
                    snapshotProperties(strongVC, @"ActVC(completion后)");
                }
            };
            [vcInstance performSelector:@selector(showSuccess:completion:) withObject:@"到期时间:2099-12-31 23:59:59" withObject:completionBlock];
            LOG(@"✅ showSuccess:completion: 已调用");
        }
    } @catch (NSException *e) {
        LOG(@"❌ showSuccess:completion: 失败: %@", e.reason);
    }
    
    // 5. 调用 buildSuccessViewWithExpire:
    @try {
        if ([vcInstance respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            [vcInstance performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"到期时间:2099-12-31 23:59:59"];
            LOG(@"✅ buildSuccessViewWithExpire: 已调用");
        }
    } @catch (NSException *e) { LOG(@"❌ buildSuccessViewWithExpire: %@", e.reason); }
    
    // ============================================================
    // ⭐ v14 核心修复：设置 MainVC.state 触发数据加载 + 显式刷新
    // ============================================================
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LOG(@"⭐ 开始修复 MainVC state...");
        
        Class mainVCClass = objc_getClass("ViewController");
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            UIViewController *root = window.rootViewController;
            if ([root isKindOfClass:mainVCClass]) {
                LOG(@"🎯 找到 MainVC");
                snapshotProperties(root, @"MainVC(修复前)");
                
                // 尝试设置 state = 1（最常见的"已验证"状态值）
                @try {
                    if ([root respondsToSelector:@selector(setState:)]) {
                        [root performSelector:@selector(setState:) withObject:@(1)];
                        LOG(@"✅ setState:1 已调用");
                    }
                    // 也尝试直接设置 _state ivar
                    Ivar stateIvar = class_getInstanceVariable([root class], "_state");
                    if (stateIvar) {
                        object_setIvar(root, stateIvar, @(1));
                        LOG(@"✅ _state = 1 (直接设置ivar)");
                    }
                } @catch (NSException *e) {
                    LOG(@"❌ setState:1 失败: %@", e.reason);
                }
                
                // 尝试设置 statusText
                @try {
                    if ([root respondsToSelector:@selector(setStatusText:)]) {
                        [root performSelector:@selector(setStatusText:) withObject:@"已激活"];
                        LOG(@"✅ setStatusText: 已调用");
                    }
                } @catch (NSException *e) {}
                
                // 尝试调用 viewDidLoad 重新加载（如果它内部有根据 state 加载数据的逻辑）
                @try {
                    if ([root respondsToSelector:@selector(viewDidLoad)]) {
                        // 不要直接调 viewDidLoad，尝试找可能的数据加载方法
                        // 常见命名：loadData、refreshData、reloadData、fetchData、updateData
                        NSArray *possibleMethods = @[
                            @"loadData", @"refreshData", @"reloadData", @"fetchData", @"updateData",
                            @"loadConfig", @"refreshConfig", @"fetchConfig", @"updateConfig",
                            @"startRadar", @"startLoading", @"initialize", @"setupUI",
                            @"loadContent", @"refreshContent", @"updateUI", @"renderUI"
                        ];
                        for (NSString *methodName in possibleMethods) {
                            SEL sel = NSSelectorFromString(methodName);
                            if ([root respondsToSelector:sel]) {
                                [root performSelector:sel];
                                LOG(@"✅ 调用 %@ 成功", methodName);
                                break;
                            }
                        }
                    }
                } @catch (NSException *e) {
                    LOG(@"❌ 数据加载方法调用失败: %@", e.reason);
                }
                
                // ============================================================
                // ➕ 新增：显式调用 setup、reloadData 和 tableView 刷新
                // ============================================================
                if ([root respondsToSelector:@selector(setup)]) {
                    [root performSelector:@selector(setup)];
                    LOG(@"✅ setup 已调用");
                }
                
                if ([root respondsToSelector:@selector(reloadData)]) {
                    [root performSelector:@selector(reloadData)];
                    LOG(@"✅ reloadData 已调用");
                }
                
                id tableView = [root valueForKey:@"tableView"];
                if (tableView && [tableView respondsToSelector:@selector(reloadData)]) {
                    [tableView performSelector:@selector(reloadData)];
                    LOG(@"✅ tableView reloadData 已调用");
                }
                // ============================================================
                
                // 延迟后快照
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    snapshotProperties(root, @"MainVC(修复后)");
                });
                
                break;
            }
        }
    });
    
    // 6. 延迟 dismiss
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([vcInstance isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)vcInstance;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:^{
                        LOG(@"✅ dismiss 完成");
                    }];
                }
            }
        } @catch (NSException *e) {}
    });
}

// ============================================================
// Hook 入口
// ============================================================
static void hookActivationVC(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 WWWActivationViewController"); return; }
    LOG(@"🎣 Hook: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [ActVC] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
        LOG(@"  ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(onTapVerify));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 onTapVerify 拦截");
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(onTapVerify), newIMP, typeEnc);
        LOG(@"  ✅ onTapVerify");
    }
    
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSString *msg) {
            LOG(@"🛡️ showError 拦截: %@", msg);
            doBypass(self);
        });
        class_replaceMethod(cls, @selector(showError:), newIMP, typeEnc);
        LOG(@"  ✅ showError:");
    }
    
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            return YES;
        });
        class_replaceMethod(cls, @selector(isActivated), newIMP, typeEnc);
        LOG(@"  ✅ isActivated -> YES");
    }
    
    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) {
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            return YES;
        });
        class_replaceMethod(cls, @selector(isVerified), newIMP, typeEnc);
        LOG(@"  ✅ isVerified -> YES");
    }
}

static void hookViewController(Class cls) {
    if (!cls) { LOG(@"❌ 未找到 ViewController"); return; }
    LOG(@"🎣 Hook MainVC: %s", class_getName(cls));
    
    Method m;
    
    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self) {
            LOG(@"🎯 [MainVC] viewDidLoad");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
            snapshotProperties(self, @"MainVC(viewDidLoad)");
        });
        class_replaceMethod(cls, @selector(viewDidLoad), newIMP, typeEnc);
        LOG(@"  ✅ viewDidLoad");
    }
    
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, BOOL animated) {
            LOG(@"🎯 [MainVC] viewDidAppear:");
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
            snapshotProperties(self, @"MainVC(viewDidAppear)");
        });
        class_replaceMethod(cls, @selector(viewDidAppear:), newIMP, typeEnc);
        LOG(@"  ✅ viewDidAppear:");
    }
    
    // ⭐ v14 新增：监听 setState: 变化
    m = class_getInstanceMethod(cls, @selector(setState:));
    if (m) {
        IMP orig = method_getImplementation(m);
        const char *typeEnc = method_getTypeEncoding(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, NSInteger state) {
            LOG(@"🔔 [MainVC] setState: %ld", (long)state);
            ((void (*)(id, SEL, NSInteger))orig)(self, @selector(setState:), state);
            snapshotProperties(self, [NSString stringWithFormat:@"MainVC(setState:%ld)", (long)state]);
        });
        class_replaceMethod(cls, @selector(setState:), newIMP, typeEnc);
        LOG(@"  ✅ setState: (监听)");
    }
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunV14] v14 state修复版+显式刷新已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        
        Class vcClass = objc_getClass("WWWActivationViewController");
        if (vcClass) hookActivationVC(vcClass);
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        
        LOG(@"🚀 初始化完成 v14");
        LOG(@"📋 操作：打开软件 → 点验证 → 观察主页面是否加载内容");
        LOG(@"📋 如果仍空白，复制日志发给我，我会调整 state 值");
    });
}
