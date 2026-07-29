//
//  iphook.m - KFun 修复工具 v3 (不闪退版)
//  GitHub Actions 单文件编译，注入稳定不崩
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 日志

static UITextView *gLog = nil;
static NSMutableString *gBuf = nil;

static void KLog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    NSString *line = [NSString stringWithFormat:@"[%.2f] %@", [[NSDate date] timeIntervalSince1970], m];
    NSLog(@"[KFunFix] %@", line);
    if (!gBuf) gBuf = [NSMutableString string];
    [gBuf appendFormat:@"%@\n", line];
    if (gBuf.length > 20000) [gBuf deleteCharactersInRange:NSMakeRange(0, gBuf.length-20000)];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gLog) { gLog.text = gBuf; [gLog scrollRangeToVisible:NSMakeRange(gBuf.length-1, 1)]; }
    });
}

#pragma mark - 悬浮窗

@interface KFDrag : NSObject
@property (nonatomic, strong) NSMutableDictionary *origIMPs;
@end

@implementation KFDrag
- (instancetype)init {
    self = [super init];
    if (self) _origIMPs = [NSMutableDictionary dictionary];
    return self;
}
- (void)pan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view.superview;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x+t.x, v.center.y+t.y);
    [p setTranslation:CGPointZero inView:v.superview];
}
- (void)copyLog:(id)s { if (gBuf.length) [UIPasteboard generalPasteboard].string = gBuf; KLog(@"📋 已复制 %lu 字符", (unsigned long)gBuf.length); }
@end

static KFDrag *gDrag = nil;
static UIView *gPanel = nil;

static UIWindow *keyWindow() {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && ((UIWindowScene*)s).activationState == UISceneActivationStateForegroundActive)
                return ((UIWindowScene*)s).windows.firstObject;
        }
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *kw = [UIApplication sharedApplication].keyWindow;
    if (!kw) kw = [UIApplication sharedApplication].windows.firstObject;
    #pragma clang diagnostic pop
    return kw;
}

static void setupUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *kw = keyWindow();
        if (!kw) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ setupUI(); }); return; }
        CGFloat w = 350, h = 420;
        gPanel = [[UIView alloc] initWithFrame:CGRectMake(10, 140, w, h)];
        gPanel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.93];
        gPanel.layer.cornerRadius = 14;
        gPanel.layer.borderWidth = 1.5;
        gPanel.layer.borderColor = [UIColor colorWithRed:0 green:0.75 blue:1 alpha:1].CGColor;
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,34)];
        bar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        [gPanel addSubview:bar];
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(8,5,220,24)];
        t.text = @"🔧 KFun 修复工具 v3"; t.textColor = [UIColor cyanColor];
        t.font = [UIFont boldSystemFontOfSize:13];
        [bar addSubview:t];
        UIButton *cb = [UIButton buttonWithType:UIButtonTypeSystem];
        cb.frame = CGRectMake(w-75,5,70,24);
        [cb setTitle:@"📋复制" forState:UIControlStateNormal];
        cb.titleLabel.font = [UIFont systemFontOfSize:10];
        [cb setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        gDrag = [[KFDrag alloc] init];
        [cb addTarget:gDrag action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:cb];
        gLog = [[UITextView alloc] initWithFrame:CGRectMake(4,78,w-8,h-82)];
        gLog.textColor = [UIColor colorWithRed:0.2 green:1 blue:0.3 alpha:1];
        gLog.font = [UIFont fontWithName:@"Menlo" size:9];
        gLog.backgroundColor = [UIColor clearColor];
        gLog.editable = NO;
        [gPanel addSubview:gLog];
        NSArray *btns = @[@{@"t":@"🔍扫描类",@"a":@"scan"}, @{@"t":@"🗑除遮罩",@"a":@"removeMask"}, @{@"t":@"🚀初始化",@"a":@"doInit"}, @{@"t":@"📊主VC",@"a":@"dumpMain"}, @{@"t":@"🎣Hook",@"a":@"doHook"}, @{@"t":@"🧪测试",@"a":@"test"}];
        for (int i=0; i<btns.count; i++) {
            int row = i/3, col = i%3;
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(6+col*114, 38+row*34, 110, 30);
            b.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
            b.layer.cornerRadius = 6;
            [b setTitle:btns[i][@"t"] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:10];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [b addTarget:gDrag action:NSSelectorFromString([btns[i][@"a"] stringByAppendingString:@":"]) forControlEvents:UIControlEventTouchUpInside];
            [gPanel addSubview:b];
        }
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gDrag action:@selector(pan:)];
        [bar addGestureRecognizer:pan];
        [kw addSubview:gPanel];
        KLog(@"✅ 修复工具已启动");
        KLog(@"📋 操作顺序：1.点🗑除遮罩 2.点🔍扫描类 3.点🚀初始化");
    });
}

#pragma mark - 工具函数

static NSArray *allWindows() {
    if (@available(iOS 13.0, *)) {
        NSMutableArray *a = [NSMutableArray array];
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) [a addObjectsFromArray:((UIWindowScene*)s).windows];
        }
        if (a.count) return a;
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].windows;
    #pragma clang diagnostic pop
}

static id findInstanceOfClass(Class cls) {
    if (!cls) return nil;
    for (UIWindow *w in allWindows()) {
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w.rootViewController];
        while (stack.count) {
            UIViewController *vc = [stack lastObject]; [stack removeLastObject];
            if ([vc isKindOfClass:cls]) return vc;
            if (vc.presentedViewController) [stack addObject:vc.presentedViewController];
            if ([vc isKindOfClass:[UINavigationController class]]) [stack addObjectsFromArray:((UINavigationController*)vc).viewControllers];
            if ([vc isKindOfClass:[UITabBarController class]]) [stack addObjectsFromArray:((UITabBarController*)vc).viewControllers];
            [stack addObjectsFromArray:vc.childViewControllers];
        }
    }
    return nil;
}

static void dumpObj(id obj, NSString *tag) {
    if (!obj) { KLog(@"[%@] nil", tag); return; }
    KLog(@"┌── 📸 [%@] %@", tag, NSStringFromClass([obj class]));
    unsigned int n; objc_property_t *p = class_copyPropertyList([obj class], &n);
    for (unsigned int i=0; i<n && i<40; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(p[i])];
        @try {
            id v = [obj valueForKey:name];
            NSString *d = v ? [v description] : @"nil";
            if (d.length > 180) d = [d substringToIndex:180];
            KLog(@"│ %@ = %@", name, d);
        } @catch (NSException *e) { KLog(@"│ %@ = [err]", name); }
    }
    if (p) free(p);
    KLog(@"└──");
}

static Class findClassBySelector(SEL sel) {
    int total = objc_getClassList(NULL, 0);
    Class *buf = (Class*)malloc(sizeof(Class)*total);
    objc_getClassList(buf, total);
    Class r = Nil;
    for (int i=0; i<total; i++) {
        if (class_getInstanceMethod(buf[i], sel)) { r = buf[i]; break; }
    }
    free(buf);
    return r;
}

#pragma mark - 按钮动作

@implementation KFDrag (Actions)

- (void)scan:(id)sender {
    KLog(@"🔍 扫描关键方法所在类...");
    SEL sels[] = {@selector(activateCode:completion:), @selector(verifyWithCompletion:), @selector(setupAfterActivation), @selector(showSuccess:completion:), @selector(buildSuccessViewWithExpire:), @selector(onTapVerify), @selector(showError:), @selector(prefillCode:), nil};
    for (int i=0; sels[i]!=nil; i++) {
        Class c = findClassBySelector(sels[i]);
        KLog(@"   %s → %@", sel_getName(sels[i]), c ? NSStringFromClass(c) : @"(未找到)");
    }
    KLog(@"🔍 扫描完成");
}

- (void)removeMask:(id)sender {
    int cnt = 0;
    for (UIWindow *w in allWindows()) {
        NSArray *subs = [w.subviews copy];
        for (UIView *v in subs) {
            NSString *cls = NSStringFromClass([v class]);
            if ([cls containsString:@"Mask"] || [cls containsString:@"Auth"] || v.alpha < 0.95 || v.tag == 9999) {
                [v removeFromSuperview]; cnt++;
                KLog(@"🗑 移除遮罩类: %@", cls);
            }
            @try {
                if ([v respondsToSelector:@selector(authMaskView)]) {
                    UIView *m = [v performSelector:@selector(authMaskView)];
                    if (m) { [m removeFromSuperview]; cnt++; KLog(@"🗑 KVC 移除 authMaskView"); }
                }
            } @catch (id e) {}
        }
    }
    KLog(@"🗑 共移除 %d 个遮罩", cnt);
}

- (void)doInit:(id)sender {
    Class c = findClassBySelector(@selector(setupAfterActivation));
    if (c) {
        id inst = findInstanceOfClass(c);
        if (inst) {
            KLog(@"🚀 调用 [%@ setupAfterActivation]", NSStringFromClass(c));
            dumpObj(inst, @"BeforeSetup");
            [inst performSelector:@selector(setupAfterActivation)];
            dumpObj(inst, @"AfterSetup");
        } else {
            KLog(@"⚠️ 找到类 %@ 但无实例", NSStringFromClass(c));
        }
    } else {
        KLog(@"❌ 未找到 setupAfterActivation");
    }
    Class c2 = findClassBySelector(@selector(showSuccess:completion:));
    if (c2) {
        id i2 = findInstanceOfClass(c2);
        if (i2) {
            KLog(@"🚀 调用 [%@ showSuccess:completion:]", NSStringFromClass(c2));
            [i2 performSelector:@selector(showSuccess:completion:) withObject:@"2099-12-31" withObject:nil];
        }
    }
    Class c3 = findClassBySelector(@selector(buildSuccessViewWithExpire:));
    if (c3) {
        id i3 = findInstanceOfClass(c3);
        if (i3) {
            KLog(@"🚀 调用 [%@ buildSuccessViewWithExpire:]", NSStringFromClass(c3));
            [i3 performSelector:@selector(buildSuccessViewWithExpire:) withObject:@"2099-12-31"];
        }
    }
}

- (void)dumpMain:(id)sender {
    int total = objc_getClassList(NULL, 0);
    Class *buf = (Class*)malloc(sizeof(Class)*total);
    objc_getClassList(buf, total);
    for (int i=0; i<total; i++) {
        if ([buf[i] isSubclassOfClass:[UIViewController class]] && buf[i] != [UIViewController class]) {
            NSString *nm = NSStringFromClass(buf[i]);
            if ([nm isEqualToString:@"ViewController"] || [nm containsString:@"Main"] || [nm containsString:@"Root"] || [nm containsString:@"Game"]) {
                id inst = findInstanceOfClass(buf[i]);
                if (inst) { dumpObj(inst, nm); break; }
            }
        }
    }
    free(buf);
}

- (void)doHook:(id)sender {
    KLog(@"🎣 开始安全 Hook...");
    SEL targets[] = {@selector(activateCode:completion:), @selector(verifyWithCompletion:), @selector(setupAfterActivation), @selector(showSuccess:completion:), @selector(onTapVerify), nil};
    for (int i=0; targets[i]!=nil; i++) {
        Class c = findClassBySelector(targets[i]);
        if (!c) continue;
        NSString *cn = NSStringFromClass(c);
        NSString *bundle = [[NSBundle bundleForClass:c] bundlePath];
        if ([bundle containsString:@"/System/"] || [bundle containsString:@"/usr/lib/"]) { KLog(@"⚠️ 跳过系统类 %@", cn); continue; }
        SEL sel = targets[i];
        Method m = class_getInstanceMethod(c, sel);
        if (!m) continue;
        IMP orig = method_getImplementation(m);
        const char *te = method_getTypeEncoding(m);
        NSString *key = [NSString stringWithFormat:@"%@-%@", cn, NSStringFromSelector(sel)];
        if ([self.origIMPs objectForKey:key]) { KLog(@"⏭ %@ 已hook", key); continue; }
        [self.origIMPs setObject:[NSValue valueWithPointer:orig] forKey:key];
        if (sel == @selector(activateCode:completion:)) {
            IMP newIMP = imp_implementationWithBlock(^(id self, NSString *code, id completion) {
                KLog(@"🎯 [%@] activateCode: %@", cn, code);
                dumpObj(self, [NSString stringWithFormat:@"%@_activate", cn]);
                IMP o = [[gDrag.origIMPs objectForKey:key] pointerValue];
                ((void (*)(id, SEL, id, id))o)(self, sel, code, completion);
            });
            class_replaceMethod(c, sel, newIMP, te);
        } else if (sel == @selector(verifyWithCompletion:)) {
            IMP newIMP = imp_implementationWithBlock(^(id self, id completion) {
                KLog(@"🎯 [%@] verifyWithCompletion", cn);
                IMP o = [[gDrag.origIMPs objectForKey:key] pointerValue];
                ((void (*)(id, SEL, id))o)(self, sel, completion);
            });
            class_replaceMethod(c, sel, newIMP, te);
        } else if (sel == @selector(setupAfterActivation)) {
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                KLog(@"🎯 [%@] setupAfterActivation", cn);
                dumpObj(self, [NSString stringWithFormat:@"%@_setup", cn]);
                IMP o = [[gDrag.origIMPs objectForKey:key] pointerValue];
                ((void (*)(id, SEL))o)(self, sel);
            });
            class_replaceMethod(c, sel, newIMP, te);
        } else if (sel == @selector(showSuccess:completion:)) {
            IMP newIMP = imp_implementationWithBlock(^(id self, id expire, id completion) {
                KLog(@"🎯 [%@] showSuccess: %@", cn, expire);
                IMP o = [[gDrag.origIMPs objectForKey:key] pointerValue];
                ((void (*)(id, SEL, id, id))o)(self, sel, expire, completion);
            });
            class_replaceMethod(c, sel, newIMP, te);
        } else if (sel == @selector(onTapVerify)) {
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                KLog(@"🎯 [%@] onTapVerify", cn);
                dumpObj(self, [NSString stringWithFormat:@"%@_tap", cn]);
                IMP o = [[gDrag.origIMPs objectForKey:key] pointerValue];
                ((void (*)(id, SEL))o)(self, sel);
            });
            class_replaceMethod(c, sel, newIMP, te);
        }
        KLog(@"✅ Hooked %@", key);
    }
    KLog(@"🎣 Hook 完成");
}

- (void)test:(id)sender {
    KLog(@"🧪 测试网络通道...");
    NSURLSession *s = [NSURLSession sharedSession];
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://httpbin.org/get"]];
    NSURLSessionDataTask *t = [s dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSHTTPURLResponse *h = [r isKindOfClass:[NSHTTPURLResponse class]] ? (id)r : nil;
        KLog(@"🧪 测试响应: %ld", (long)(h?h.statusCode:0));
    }];
    [t resume];
    KLog(@"🧪 测试请求已发送");
}

@end

#pragma mark - Constructor

__attribute__((constructor))
static void iphook_init() {
    NSLog(@"========================================");
    NSLog(@"[KFunFix] v3 已加载 (不闪退版)");
    NSLog(@"========================================");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupUI();
    });
}
