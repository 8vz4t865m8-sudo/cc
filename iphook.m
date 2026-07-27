//
//  iphook.m - KFun Bypass v15
//  修复：NSInteger 类型 state 的正确写入方式
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
    NSLog(@"[KFunV15] %@", line);
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
        title.text = @"🔍 KFun v15 NSInteger修复 (拖动)";
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
        LOG(@"✅ 悬浮窗已启动 v15");
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
// 🚀 Bypass 核心 - v15 修复版
// 核心修复：NSInteger 类型 state 的正确写入
// ============================================================
static void doBypass(id vcInstance) {
    LOG(@"🚀 Bypass v15 开始");
    
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
    // ⭐ v15 核心修复：正确设置 MainVC.state (NSInteger)
    // ============================================================
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LOG(@"⭐ 开始修复 MainVC state (NSInteger)...");
        
        Class mainVCClass = objc_getClass("ViewController");
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            UIViewController *root = window.rootViewController;
            if (![root isKindOfClass:mainVCClass]) continue;
            
            LOG(@"🎯 找到 MainVC: %@", root);
            snapshotProperties(root, @"MainVC(修复前)");
            
            // 方法1：NSInvocation 正确调用 setState: (NSInteger 参数)
            @try {
                if ([root respondsToSelector:@selector(setState:)]) {
                    NSMethodSignature *sig = [root methodSignatureForSelector:@selector(setState:)];
                    if (sig) {
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setTarget:root];
                        [inv setSelector:@selector(setState:)];
                        NSInteger newState = 1;
                        [inv setArgument:&newState atIndex:2];
                        [inv invoke];
                        LOG(@"✅ NSInvocation setState:%ld 已调用", (long)newState);
                    }
                }
            } @catch (NSException *e) {
                LOG(@"❌ NSInvocation setState: 失败: %@", e.reason);
            }
            
            // 方法2：objc_msgSend 直接发送 (双重保险)
            @try {
                if ([root respondsToSelector:@selector(setState:)]) {
                    ((void (*)(id, SEL, NSInteger))objc_msgSend)(root, @selector(setState:), 1);
                    LOG(@"✅ objc_msgSend setState:1 已调用");
                }
            } @catch (NSException *e) {
                LOG(@"❌ objc_msgSend setState: 失败: %@", e.reason);
            }
            
            // 方法3：直接写 _state ivar 内存 (最终保险)
            @try {
                Ivar stateIvar = class_getInstanceVariable([root class], "_state");
                if (stateIvar) {
                    ptrdiff_t offset = ivar_getOffset(stateIvar);
                    void *objPtr = (__bridge void *)root;
                    NSInteger *statePtr = (NSInteger *)((char *)objPtr + offset);
                    *statePtr = 1;
                    LOG(@"✅ _state ivar 直接写入 = 1 (offset=%td, ptr=%p)", offset, statePtr);
                } else {
                    LOG(@"⚠️ 未找到 _state ivar");
                }
            } @catch (NSException *e) {
                LOG(@"❌ _state ivar 写入失败: %@", e.reason);
            }
            
            // 设置 statusText
            @try {
                if ([root respondsToSelector:@selector(setStatusText:)]) {
                    [root performSelector:@selector(setStatusText:) withObject:@"已激活"];
                    LOG(@"✅ setStatusText: 已调用");
                }
            } @catch (NSException *e) {}
            
            // 设置 dataText
            @try {
                if ([root respondsToSelector:@selector(setDataText:)]) {
                    [root performSelector:@selector(setDataText:) withObject:@"连接成功"];
                    LOG(@"✅ setDataText: 已调用");
                }
            } @catch (NSException *e) {}
            
            // 延迟后再次触发 viewDidAppear:，让 MainVC 重新检查 state 并加载数据
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try {
                    if ([root respondsToSelector:@selector(viewDidAppear:)]) {
                        // 使用 NSInvocation 调用，避免 performSelector 参数类型问题
                        NSMethodSignature *sig = [root methodSignatureForSelector:@selector(viewDidAppear:)];
                        if (sig) {
                            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                            [inv setTarget:root];
                            [inv setSelector:@selector(viewDidAppear:)];
                            BOOL anim = NO;
                            [inv setArgument:&anim atIndex:2];
                            [inv invoke];
                            LOG(@"✅ 重新触发 viewDidAppear:");
                        }
                    }
                } @catch (NSException *e) {
                    LOG(@"❌ viewDidAppear: 触发失败: %@", e.reason);
                }
                
                // 最终快照
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    snapshotProperties(root, @"MainVC(最终)");
                });
            });
            
            break; // 只处理第一个匹配的
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
            LOG(@"🎯 [MainVC] viewDidAppear: (state=%@)", [self valueForKey:@"state"]);
            ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
            snapshotProperties(self, @"MainVC(viewDidAppear)");
        });
        class_replaceMethod(cls, @selector(viewDidAppear:), newIMP, typeEnc);
        LOG(@"  ✅ viewDidAppear:");
    }
    
    // 监听 setState: 变化
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
    NSLog(@"[KFunV15] v15 NSInteger修复版已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        
        Class vcClass = objc_getClass("WWWActivationViewController");
        if (vcClass) hookActivationVC(vcClass);
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        
        LOG(@"🚀 初始化完成 v15");
        LOG(@"📋 操作：打开软件 → 点验证 → 观察主页面是否加载内容");
    });
}
