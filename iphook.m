//
//  iphook.m - KFun Bypass v16
//  方法级绕过：直接 Hook verifyWithCompletion: 返回假成功
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) logLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])

// ============================================================
// 调试悬浮窗
// ============================================================
static UITextView *g_logView = nil;
static UIView *g_logContainer = nil;
static NSMutableString *g_logBuffer = nil;

static void logLine(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@", [[NSDate date] timeIntervalSince1970], msg];
    NSLog(@"[KFunV16] %@", line);
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
        title.text = @"🔍 KFun v16 (方法绕过)";
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
// 伪造的验证成功数据（请务必根据应用真实返回格式修改）
// ============================================================
static id fakeSuccessResponse() {
    // 常见格式：字典，包含 code、expire、msg 等
    return @{
        @"code": @200,
        @"expire": @"2099-12-31 23:59:59",
        @"msg": @"success"
    };
}

// ============================================================
// 安全调用 completion block（自动适配参数个数）
// ============================================================
static void invokeCompletion(id completionBlock) {
    if (!completionBlock) return;
    
    // 获取 block 的方法签名
    // 参考: https://stackoverflow.com/questions/9048305/checking-objective-c-block-type
    // 使用 Block_copy 获取 block 内部结构，但这里直接用 runtime 获取 signature
    Method m = class_getInstanceMethod([NSObject class], @selector(methodSignatureForSelector:));
    // 更简单的方式：通过 objc_msgSend 直接调用，但需要知道参数个数。
    
    // 使用 NSInvocation 更麻烦，这里提供一个根据常见参数个数尝试的方案。
    // 我们先通过 block 的 signature 动态生成 NSInvocation，但考虑到兼容性，
    // 这里直接尝试调用常见的 2 参数 (id response, id error) 形式。
    // 如果应用使用了其他形式，可以观察日志中的崩溃信息再调整。
    
    // 获取 block 的函数指针
    // 定义常见类型
    void (^twoParamCompletion)(id, id) = completionBlock;   // 可能 crash 如果类型不匹配
    if (twoParamCompletion) {
        LOG(@"🎯 调用 completion (response, error)...");
        twoParamCompletion(fakeSuccessResponse(), nil);
        LOG(@"✅ completion 调用完成");
        return;
    }
    
    // 备用：尝试单参数 (id response)
    void (^oneParamCompletion)(id) = completionBlock;
    if (oneParamCompletion) {
        LOG(@"🎯 调用 completion (response)...");
        oneParamCompletion(fakeSuccessResponse());
        return;
    }
    
    // 再备用：无参数
    void (^zeroParamCompletion)(void) = completionBlock;
    if (zeroParamCompletion) {
        LOG(@"🎯 调用 completion (void)...");
        zeroParamCompletion();
        return;
    }
    
    LOG(@"❌ 无法确定 completion 的参数类型，未调用");
}

// ============================================================
// 核心 Hook: verifyWithCompletion: 直接返回成功
// ============================================================
static void hookVerifyWithCompletion(Class cls) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(verifyWithCompletion:));
    if (!m) {
        LOG(@"⚠️ 未找到 verifyWithCompletion: 方法");
        return;
    }
    
    // 获取方法类型编码，辅助判断参数
    const char *typeEnc = method_getTypeEncoding(m);
    LOG(@"📐 verifyWithCompletion: 类型编码: %s", typeEnc);
    // 通常为 v@:@?  表示参数2是 block（id 类型）
    
    // 保存原始实现（如果有用，我们这里不会调用原始实现）
    // IMP orig = method_getImplementation(m);
    
    // 新实现：直接调用传入的 completion block
    IMP newIMP = imp_implementationWithBlock(^(id self, id completion) {
        LOG(@"🔁 verifyWithCompletion: 被拦截");
        LOG(@"   completion: %@", completion);
        
        // 模拟一些可能的前置 UI 操作（如果有需要，可调用原方法的一些前置代码，
        // 但这里我们直接回调成功）
        
        // 调用原始 completion，传入假成功数据
        @try {
            invokeCompletion(completion);
        } @catch (NSException *exception) {
            LOG(@"❌ 调用 completion 异常: %@", exception.reason);
            // 出现异常说明参数类型不匹配，请根据日志调整 invokeCompletion
        }
        
        // 原 verifyWithCompletion: 可能还会返回一些对象或做其他操作，我们直接跳过
    });
    
    class_replaceMethod(cls, @selector(verifyWithCompletion:), newIMP, typeEnc);
    LOG(@"✅ verifyWithCompletion: 已 Hook（直接返回假成功）");
}

// ============================================================
// 其他辅助 Hook
// ============================================================
static void hookIsActivated(Class cls) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) {
        IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
        class_replaceMethod(cls, @selector(isActivated), newIMP, method_getTypeEncoding(m));
        LOG(@"✅ isActivated -> YES");
    }
    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) {
        IMP newIMP = imp_implementationWithBlock(^(id self) { return YES; });
        class_replaceMethod(cls, @selector(isVerified), newIMP, method_getTypeEncoding(m));
        LOG(@"✅ isVerified -> YES");
    }
}

// ============================================================
// 调试：记录关键方法调用
// ============================================================
static void hookForLogging(Class cls, SEL sel, NSString *desc) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    const char *typeEnc = method_getTypeEncoding(m);
    IMP newIMP = imp_implementationWithBlock(^(id self) {
        LOG(@"👀 %@ 被调用", desc);
        ((void (*)(id, SEL))orig)(self, sel);
    });
    class_replaceMethod(cls, sel, newIMP, typeEnc);
}

// ============================================================
// 初始化入口
// ============================================================
__attribute__((constructor))
static void iphook_init() {
    NSLog(@"[KFunV16] 方法级绕过版已加载");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupLogWindow();
        
        // 目标类
        Class actVC = objc_getClass("WWWActivationViewController");
        if (actVC) {
            LOG(@"🎯 找到 WWWActivationViewController");
            
            // 1. Hook 核心验证方法
            hookVerifyWithCompletion(actVC);
            
            // 2. 强制激活状态
            hookIsActivated(actVC);
            
            // 3. 记录一些方法用于调试（可选，可注释掉减少日志）
            hookForLogging(actVC, @selector(viewDidLoad), @"ActVC viewDidLoad");
            hookForLogging(actVC, @selector(buildSuccessViewWithExpire:), @"ActVC buildSuccessViewWithExpire:");
            hookForLogging(actVC, @selector(setupAfterActivation), @"ActVC setupAfterActivation");
        } else {
            LOG(@"❌ 未找到 WWWActivationViewController");
        }
        
        // 可选：记录主界面加载
        Class mainVC = objc_getClass("ViewController");
        if (mainVC) {
            hookForLogging(mainVC, @selector(viewDidLoad), @"MainVC viewDidLoad");
            hookForLogging(mainVC, @selector(viewDidAppear:), @"MainVC viewDidAppear:");
        }
        
        LOG(@"🚀 初始化完成，等待用户点击验证...");
    });
}
