//
//  kfun_recorder.m
//  正版卡密记录版 - 只记录，不拦截，不卡
//  编译: clang -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//        -framework UIKit -framework Foundation -dynamiclib -o kfun_recorder.dylib kfun_recorder.m
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
    NSLog(@"[KFunRec] %@", line);
    if (!g_logBuffer) g_logBuffer = [[NSMutableString alloc] init];
    [g_logBuffer appendFormat:@"%@\n", line];
    if (g_logBuffer.length > 20000) {
        [g_logBuffer deleteCharactersInRange:NSMakeRange(0, g_logBuffer.length - 20000)];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = g_logBuffer;
            [g_logView scrollRangeToVisible:NSMakeRange(g_logBuffer.length - 1, 1)];
        }
    });
}

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
        LOG(@"📋 已复制 (%lu 字符)", (unsigned long)g_logBuffer.length);
    }
}
@end
static DragHandler *g_drag = nil;

static void setupWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DragHandler *dh = [[DragHandler alloc] init];
        g_drag = dh;
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)s).activationState == UISceneActivationStateForegroundActive) {
                    if (((UIWindowScene *)s).windows.count) { kw = ((UIWindowScene *)s).windows.firstObject; break; }
                }
            }
        }
        if (!kw) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            kw = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
            #pragma clang diagnostic pop
        }
        if (!kw) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupWindow(); }); return; }
        
        CGFloat w = 350, h = 280;
        g_logContainer = [[UIView alloc] initWithFrame:CGRectMake(8, 100, w, h)];
        g_logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.93];
        g_logContainer.layer.cornerRadius = 10;
        g_logContainer.layer.borderColor = [UIColor cyanColor].CGColor;
        g_logContainer.layer.borderWidth = 1.2;
        
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 26)];
        bar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        [g_logContainer addSubview:bar];
        
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(6, 3, w-80, 20)];
        t.text = @"🔍 正版记录版 (拖动)";
        t.textColor = [UIColor cyanColor];
        t.font = [UIFont boldSystemFontOfSize:10];
        [bar addSubview:t];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w-70, 2, 65, 22);
        [copyBtn setTitle:@"📋复制" forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont systemFontOfSize:9];
        [copyBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        [copyBtn addTarget:dh action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:copyBtn];
        
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
        LOG(@"✅ 记录器启动");
        LOG(@"📋 请用正版卡密正常验证");
    });
}

// 轻量快照：只打印关键属性
static void snap(id obj, NSString *label) {
    if (!obj) return;
    LOG(@"📸 [%@] %@", label, NSStringFromClass([obj class]));
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(object_getClass(obj), &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
        // 只关注关键属性，减少日志量
        if (![name isEqualToString:@"state"] && 
            ![name isEqualToString:@"tableView"] && 
            ![name isEqualToString:@"statusText"] && 
            ![name isEqualToString:@"dataText"] && 
            ![name isEqualToString:@"authMaskView"] &&
            ![name hasPrefix:@"busy"] &&
            ![name hasSuffix:@"Data"] &&
            ![name hasSuffix:@"Result"] &&
            ![name hasSuffix:@"Response"] &&
            ![name hasSuffix:@"Info"] &&
            ![name hasSuffix:@"Config"] &&
            ![name hasSuffix:@"Token"] &&
            ![name hasSuffix:@"Key"]) continue;
        
        @try {
            id val = [obj valueForKey:name];
            NSString *desc = val ? [val description] : @"nil";
            if (desc.length > 120) desc = [desc substringToIndex:120];
            LOG(@"   %@ = %@", name, desc);
        } @catch (NSException *e) {}
    }
    if (props) free(props);
}

// 递归查找
static UIViewController *findVC(Class target, UIViewController *vc) {
    if (!vc) return nil;
    if ([vc isKindOfClass:target]) return vc;
    UIViewController *found = findVC(target, [vc presentedViewController]);
    if (found) return found;
    for (UIViewController *c in [vc childViewControllers]) {
        found = findVC(target, c);
        if (found) return found;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        for (UIViewController *c in [(UITabBarController *)vc viewControllers]) {
            found = findVC(target, c);
            if (found) return found;
        }
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *c in [(UINavigationController *)vc viewControllers]) {
            found = findVC(target, c);
            if (found) return found;
        }
    }
    return nil;
}

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWindow();
        
        Class actVC = objc_getClass("WWWActivationViewController");
        Class mainVC = objc_getClass("ViewController");
        
        // Hook ActVC.onTapVerify
        Method m = class_getInstanceMethod(actVC, @selector(onTapVerify));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG(@"🎯 [ActVC] onTapVerify 开始");
                snap(self, @"ActVC(点击前)");
                ((void (*)(id, SEL))orig)(self, @selector(onTapVerify));
                LOG(@"🎯 [ActVC] onTapVerify 结束");
                snap(self, @"ActVC(点击后)");
            });
            class_replaceMethod(actVC, @selector(onTapVerify), newIMP, te);
            LOG(@"✅ Hook onTapVerify");
        }
        
        // Hook ActVC.showSuccess:completion:
        m = class_getInstanceMethod(actVC, @selector(showSuccess:completion:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, id expire, id completion) {
                LOG(@"🎉 [ActVC] showSuccess:completion: expire=%@", expire);
                snap(self, @"ActVC(showSuccess前)");
                id wrapped = ^(void) {
                    LOG(@"🎉 [ActVC] completion 执行");
                    if (completion) ((void(^)(void))completion)();
                    snap(self, @"ActVC(completion后)");
                };
                ((void (*)(id, SEL, id, id))orig)(self, @selector(showSuccess:completion:), expire, wrapped);
                LOG(@"🎉 [ActVC] showSuccess:completion: 返回");
            });
            class_replaceMethod(actVC, @selector(showSuccess:completion:), newIMP, te);
            LOG(@"✅ Hook showSuccess:completion:");
        }
        
        // Hook ActVC.setupAfterActivation
        m = class_getInstanceMethod(actVC, @selector(setupAfterActivation));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG(@"🎉 [ActVC] setupAfterActivation 调用");
                ((void (*)(id, SEL))orig)(self, @selector(setupAfterActivation));
            });
            class_replaceMethod(actVC, @selector(setupAfterActivation), newIMP, te);
            LOG(@"✅ Hook setupAfterActivation");
        }
        
        // Hook MainVC.setState:
        m = class_getInstanceMethod(mainVC, @selector(setState:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, NSInteger state) {
                LOG(@"🔔 [MainVC] setState: %ld", (long)state);
                ((void (*)(id, SEL, NSInteger))orig)(self, @selector(setState:), state);
                snap(self, [NSString stringWithFormat:@"MainVC(state=%ld)", (long)state]);
            });
            class_replaceMethod(mainVC, @selector(setState:), newIMP, te);
            LOG(@"✅ Hook setState:");
        }
        
        // Hook MainVC.viewDidLoad
        m = class_getInstanceMethod(mainVC, @selector(viewDidLoad));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                LOG(@"🎯 [MainVC] viewDidLoad");
                ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
                snap(self, @"MainVC(viewDidLoad)");
            });
            class_replaceMethod(mainVC, @selector(viewDidLoad), newIMP, te);
            LOG(@"✅ Hook viewDidLoad");
        }
        
        // Hook MainVC.viewDidAppear:
        m = class_getInstanceMethod(mainVC, @selector(viewDidAppear:));
        if (m) {
            IMP orig = method_getImplementation(m);
            const char *te = method_getTypeEncoding(m);
            IMP newIMP = imp_implementationWithBlock(^(id self, BOOL anim) {
                LOG(@"🎯 [MainVC] viewDidAppear:");
                ((void (*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), anim);
                snap(self, @"MainVC(viewDidAppear)");
            });
            class_replaceMethod(mainVC, @selector(viewDidAppear:), newIMP, te);
            LOG(@"✅ Hook viewDidAppear:");
        }
        
        LOG(@"🚀 记录器就绪，请用正版卡密验证");
    });
}
