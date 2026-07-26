//
//  iphook.m - KFun Bypass 修复版 v6-fix
//  修复：ARC 桥接转换 (__bridge)
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
    NSLog(@"[KFunV6] %@", line);
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
        title.text = @"🔍 KFun v6 (拖动)";
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
// ⭐ Block 签名探测
// ============================================================
struct Block_descriptor_v1 {
    unsigned long int reserved;
    unsigned long int size;
    const char *signature;
    const char *layout;
};

struct Block_literal {
    void *isa;
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct Block_descriptor_v1 *descriptor;
};

#define BLOCK_HAS_SIGNATURE  (1 << 30)

static const char *getBlockSignature(id blockObj) {
    if (!blockObj) return NULL;
    struct Block_literal *block = (__bridge struct Block_literal *)blockObj;
    if (!(block->flags & BLOCK_HAS_SIGNATURE)) return NULL;
    return block->descriptor->signature;
}

static void safeInvokeBlock(id blockObj) {
    if (!blockObj) { LOG(@"⚠️ block 为 nil"); return; }
    
    const char *sig = getBlockSignature(blockObj);
    LOG(@"⭐ Block 原始签名: %s", sig ? sig : "无");
    
    if (!sig) {
        LOG(@"⚠️ 无法读取签名，放弃调用（避免闪退）");
        return;
    }
    
    int paramCount = 0;
    for (const char *p = sig; *p; p++) {
        if (*p == '@') paramCount++;
    }
    int actualParams = paramCount - 1;
    LOG(@"⭐ Block 参数个数估算: %d", actualParams);
    
    @try {
        if (actualParams <= 0) {
            typedef void (^VoidBlock)(void);
            VoidBlock blk = (VoidBlock)blockObj;
            blk();
            LOG(@"✅ 无参 block 调用成功");
        } else if (actualParams == 1) {
            typedef void (^OneParamBlock)(id);
            OneParamBlock blk = (OneParamBlock)blockObj;
            blk(@"2099-12-31 23:59:59");
            LOG(@"✅ 1参 block 调用成功 (传 NSString)");
        } else if (actualParams == 2) {
            typedef void (^TwoParamBlock)(BOOL, id);
            TwoParamBlock blk = (TwoParamBlock)blockObj;
            blk(YES, @"2099-12-31 23:59:59");
            LOG(@"✅ 2参 block 调用成功 (传 BOOL+NSString)");
        } else {
            LOG(@"⚠️ 参数太多(%d)，放弃调用避免闪退", actualParams);
        }
    } @catch (NSException *e) {
        LOG(@"❌ Block 调用失败: %@", e.reason);
    }
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
// 🚀 Bypass 核心
// ============================================================
static void doBypass(id vcInstance) {
    LOG(@"🚀 Bypass 开始");
    
    @try {
        id spinner = [vcInstance valueForKey:@"spinner"];
        if (spinner && [spinner isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)spinner stopAnimating];
            [(UIActivityIndicatorView *)spinner setHidden:YES];
            LOG(@"✅ spinner 停止");
        }
    } @catch (NSException *e) {}
    
    @try {
        id errorLabel = [vcInstance valueForKey:@"errorLabel"];
        if (errorLabel && [errorLabel isKindOfClass:[UIView class]]) {
            [(UIView *)errorLabel setHidden:YES];
        }
    } @catch (NSException *e) {}
    
    @try {
        id mask = [vcInstance valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) {
            [(UIView *)mask setHidden:YES];
            [(UIView *)mask removeFromSuperview];
            LOG(@"✅ authMaskView 移除");
        }
    } @catch (NSException *e) {}
    
    @try {
        if ([vcInstance respondsToSelector:@selector(buildSuccessViewWithExpire:)]) {
            [vcInstance performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31 23:59:59"];
            LOG(@"✅ buildSuccessViewWithExpire: 已调用");
        }
    } @catch (NSException *e) { LOG(@"❌ buildSuccessViewWithExpire: %@", e.reason); }
    
    @try {
        id onVerify = [vcInstance valueForKey:@"onVerify"];
        if (onVerify) {
            LOG(@"⭐ 发现 onVerify block");
            safeInvokeBlock(onVerify);
        } else {
            LOG(@"⚠️ onVerify 为 nil");
        }
    } @catch (NSException *e) {
        LOG(@"❌ 读取/调用 onVerify 失败: %@", e.reason);
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([vcInstance isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)vcInstance;
                if (vc.presentingViewController) {
                    [vc dismissViewControllerAnimated:NO completion:nil];
                    LOG(@"✅ dismiss 验证页");
                }
            }
        } @catch (NSException *e) {}
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Class mainVCClass = objc_getClass("ViewController");
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                UIViewController *root = window.rootViewController;
                if ([root isKindOfClass:mainVCClass]) {
                    LOG(@"🔍 找到主页面，检查状态...");
                    snapshotProperties(root, @"MainVC(修复后)");
                    break;
                }
            }
        });
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
            snapshotProperties(self, @"ActVC(viewDidLoad)");
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
}

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunV6] v6-fix 已加载");
    NSLog(@"========================================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        
        Class vcClass = objc_getClass("WWWActivationViewController");
        if (vcClass) hookActivationVC(vcClass);
        
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) hookViewController(mainVC);
        
        LOG(@"🚀 初始化完成");
        LOG(@"📋 操作：打开软件 → 点验证 → 观察日志 → 复制发给我");
    });
}
