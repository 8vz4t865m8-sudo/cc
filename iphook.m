//
//  KFun 诊断 Tweak v8 —— 极简观察版
//  原则：只记录，不干预。除了 isActivated/isVerified 返回 YES 外，不做任何干预。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static UITextView *g_tv = nil;
static UIView *g_container = nil;

static void L(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    NSLog(@"[K8] %@", s);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_tv) {
            NSString *t = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970];
            NSString *line = [NSString stringWithFormat:@"[%@] %@", t, s];
            NSString *nt = g_tv.text.length ? [NSString stringWithFormat:@"%@\n%@", g_tv.text, line] : line;
            if (nt.length > 15000) nt = [nt substringFromIndex:nt.length-15000];
            g_tv.text = nt;
            [g_tv scrollRangeToVisible:NSMakeRange(nt.length-1, 1)];
        }
    });
}

@interface LH : NSObject
@end
@implementation LH
- (void)pan:(UIPanGestureRecognizer*)p {
    UIView *v = p.view.superview;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x+t.x, v.center.y+t.y);
    [p setTranslation:CGPointZero inView:v.superview];
}
- (void)copy:(id)s {
    if (g_tv) { UIPasteboard.generalPasteboard.string = g_tv.text; L(@"📋 已复制"); }
}
@end
static LH *g_lh = nil;

static void setupWin() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
                if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene*)sc).activationState == UISceneActivationStateForegroundActive) {
                    if (((UIWindowScene*)sc).windows.count > 0) { kw = ((UIWindowScene*)sc).windows.firstObject; break; }
                }
            }
        }
        if (!kw) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            kw = [UIApplication sharedApplication].keyWindow;
            if (!kw && [UIApplication sharedApplication].windows.count > 0) kw = [UIApplication sharedApplication].windows[0];
            #pragma clang diagnostic pop
        }
        if (!kw) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ setupWin(); }); return; }

        CGFloat w=340, h=400;
        g_container = [[UIView alloc] initWithFrame:CGRectMake(10,100,w,h)];
        g_container.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.95];
        g_container.layer.cornerRadius = 10;
        g_container.layer.borderColor = [UIColor greenColor].CGColor;
        g_container.layer.borderWidth = 1.5;

        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,30)];
        bar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.98];
        [g_container addSubview:bar];

        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(8,4,w-70,22)];
        tl.text = @"🔍 KFun观察v8(拖动/点展开)";
        tl.textColor = [UIColor greenColor];
        tl.font = [UIFont boldSystemFontOfSize:11];
        [bar addSubview:tl];

        UIButton *cb = [UIButton buttonWithType:UIButtonTypeSystem];
        cb.frame = CGRectMake(w-60,4,55,22);
        [cb setTitle:@"📋复制" forState:UIControlStateNormal];
        cb.titleLabel.font = [UIFont systemFontOfSize:10];
        [cb setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
        g_lh = [[LH alloc] init];
        [cb addTarget:g_lh action:@selector(copy:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:cb];

        g_tv = [[UITextView alloc] initWithFrame:CGRectMake(2,32,w-4,h-34)];
        g_tv.textColor = [UIColor greenColor];
        g_tv.font = [UIFont fontWithName:@"Menlo" size:9];
        g_tv.backgroundColor = [UIColor clearColor];
        g_tv.editable = NO; g_tv.selectable = YES;
        g_tv.text = @"[系统] KFun观察v8已启动\n💡 只记录，不干预\n💡 输入15位假卡密 → 点验证 → 观察完整流程\n";
        [g_container addSubview:g_tv];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_lh action:@selector(pan:)];
        [bar addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:g_container action:@selector(toggle)];
        [bar addGestureRecognizer:tap];

        [kw addSubview:g_container];
        L(@"✅ 悬浮窗已创建");
    });
}

static NSString *D(id obj) {
    if (!obj) return @"nil";
    @try {
        if ([obj isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"\"%@\"", obj];
        if ([obj isKindOfClass:[NSArray class]]) return [NSString stringWithFormat:@"NSArray(count=%lu)", (unsigned long)[(NSArray*)obj count]];
        if ([obj isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"NSDictionary(count=%lu keys=%@)", (unsigned long)[(NSDictionary*)obj count], [(NSDictionary*)obj allKeys]];
        if ([obj isKindOfClass:[NSData class]]) return [NSString stringWithFormat:@"NSData(len=%lu)", (unsigned long)[(NSData*)obj length]];
        if ([obj isKindOfClass:[UIButton class]]) {
            UIButton *b = obj;
            NSString *tt = [b titleForState:UIControlStateNormal];
            return [NSString stringWithFormat:@"UIButton(title=\"%@\" frame=%@ hidden=%d)", tt?tt:@"(无)", NSStringFromCGRect(b.frame), (int)b.hidden];
        }
        return [obj description];
    } @catch (NSException *e) { return @"[err]"; }
}

static UIViewController *topVC() {
    @try {
        UIWindow *w = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
                if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene*)sc).activationState == UISceneActivationStateForegroundActive) {
                    if (((UIWindowScene*)sc).windows.count > 0) { w = ((UIWindowScene*)sc).windows.firstObject; break; }
                }
            }
        }
        if (!w) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            w = [UIApplication sharedApplication].keyWindow;
            if (!w && [UIApplication sharedApplication].windows.count > 0) w = [UIApplication sharedApplication].windows[0];
            #pragma clang diagnostic pop
        }
        if (!w) return nil;
        UIViewController *vc = w.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        return vc;
    } @catch (NSException *e) { return nil; }
}

// ============================================================
// 🖱️ 按钮点击记录（原版方式）
// ============================================================
static void (*orig_send)(id, SEL, SEL, id, id);
static void hook_send(id self, SEL _cmd, SEL action, id target, UIEvent *event) {
    if ([self isKindOfClass:[UIButton class]]) {
        NSString *act = NSStringFromSelector(action);
        NSString *tgt = target ? NSStringFromClass([target class]) : @"nil";
        L(@"🖱️ BTN %@ -> %@.%@", NSStringFromClass([self class]), tgt, act);
        NSString *tt = [((UIButton*)self) titleForState:UIControlStateNormal];
        if (tt.length) L(@"   title=\"%@\"", tt);
    }
    orig_send(self, _cmd, action, target, event);
}

// ============================================================
// 🔍 安全 dump VC 属性和 ivar
// ============================================================
static void dumpVC(UIViewController *vc, NSString *prefix) {
    if (!vc) return;
    NSString *cls = NSStringFromClass([vc class]);
    L(@"%@📂 VC: %@", prefix, cls);

    // dump 关键 ivar
    unsigned int n=0;
    Ivar *iv = class_copyIvarList([vc class], &n);
    for (unsigned int i=0; i<n; i++) {
        NSString *name = [NSString stringWithUTF8String:ivar_getName(iv[i])];
        if ([name hasPrefix:@"_"]) {
            @try {
                id v = object_getIvar(vc, iv[i]);
                if (v) L(@"%@  🔒 %@ = %@", prefix, name, D(v));
            } @catch (NSException *e) {}
        }
    }
    free(iv);

    // dump 关键 property
    objc_property_t *ps = class_copyPropertyList([vc class], &n);
    for (unsigned int i=0; i<n; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(ps[i])];
        if ([name isEqualToString:@"view"]) continue;
        @try {
            id v = [vc valueForKey:name];
            if (v) L(@"%@  📦 %@ = %@", prefix, name, D(v));
        } @catch (NSException *e) {}
    }
    free(ps);

    // dump subviews (buttons, labels, tableviews)
    if (vc.view) {
        for (UIView *v in vc.view.subviews) {
            if ([v isKindOfClass:[UIButton class]]) {
                UIButton *b = (UIButton*)v;
                NSString *tt = [b titleForState:UIControlStateNormal];
                L(@"%@  🔘 Button: \"%@\" frame=%@ hidden=%d alpha=%.2f", prefix, tt?tt:@"(无)", NSStringFromCGRect(b.frame), (int)b.hidden, b.alpha);
            } else if ([v isKindOfClass:[UILabel class]]) {
                UILabel *l = (UILabel*)v;
                if (l.text.length) L(@"%@  📝 Label: \"%@\" frame=%@ alpha=%.2f", prefix, l.text, NSStringFromCGRect(l.frame), l.alpha);
            } else if ([v isKindOfClass:[UITableView class]]) {
                UITableView *tv = (UITableView*)v;
                NSInteger sec = [tv numberOfSections];
                NSInteger rows = 0;
                for (NSInteger i=0; i<sec; i++) rows += [tv numberOfRowsInSection:i];
                L(@"%@  📋 TableView: sections=%ld rows=%ld frame=%@", prefix, (long)sec, (long)rows, NSStringFromCGRect(tv.frame));
            } else if ([v isKindOfClass:[UIActivityIndicatorView class]]) {
                L(@"%@  ⭕ Spinner: hidden=%d", prefix, (int)v.hidden);
            }
        }
    }
}

// ============================================================
// 🎣 Hook WWWActivationViewController 关键方法（只记录，不干预）
// ============================================================
static void hookActMethods(Class cls) {
    if (!cls) return;
    L(@"🎣 Hook %s 关键方法（只记录）", class_getName(cls));

    // 1. viewDidLoad —— 记录 + dump
    Method m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            L(@"🎯 [ACT] viewDidLoad");
            dumpVC(self, @"  ");
            ((void (*)(id, SEL))orig)(self, @selector(viewDidLoad));
        }));
        L(@"  ✅ viewDidLoad");
    }

    // 2. showError: —— 只记录，不干预
    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *msg) {
            L(@"🛡️ [ACT] showError: \"%@\"", msg);
            dumpVC(self, @"  ");
            ((void (*)(id, SEL, NSString*))orig)(self, @selector(showError:), msg);
        }));
        L(@"  ✅ showError:");
    }

    // 3. showSuccess:completion: —— 只记录
    m = class_getInstanceMethod(cls, @selector(showSuccess:completion:));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *msg, id completion) {
            L(@"🏆 [ACT] showSuccess: \"%@\" completion=%@", msg, D(completion));
            dumpVC(self, @"  ");
            ((void (*)(id, SEL, NSString*, id))orig)(self, @selector(showSuccess:completion:), msg, completion);
        }));
        L(@"  ✅ showSuccess:completion:");
    }

    // 4. buildSuccessViewWithExpire: —— 只记录
    m = class_getInstanceMethod(cls, @selector(buildSuccessViewWithExpire:));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *expire) {
            L(@"🏆 [ACT] buildSuccessViewWithExpire: \"%@\"", expire);
            dumpVC(self, @"  ");
            ((void (*)(id, SEL, NSString*))orig)(self, @selector(buildSuccessViewWithExpire:), expire);
        }));
        L(@"  ✅ buildSuccessViewWithExpire:");
    }

    // 5. dismissViewControllerAnimated:completion: —— 只记录
    m = class_getInstanceMethod(cls, @selector(dismissViewControllerAnimated:completion:));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL animated, id completion) {
            L(@"📱 [ACT] dismissViewControllerAnimated:%d", (int)animated);
            ((void (*)(id, SEL, BOOL, id))orig)(self, @selector(dismissViewControllerAnimated:completion:), animated, completion);
        }));
        L(@"  ✅ dismissViewControllerAnimated:");
    }

    // 6. setLoading: —— 只记录
    m = class_getInstanceMethod(cls, @selector(setLoading:));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSNumber *loading) {
            L(@"⚙️ [ACT] setLoading: %@", loading);
            ((void (*)(id, SEL, NSNumber*))orig)(self, @selector(setLoading:), loading);
        }));
        L(@"  ✅ setLoading:");
    }

    // 7. setSuccessView: —— 只记录
    m = class_getInstanceMethod(cls, @selector(setSuccessView:));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id view) {
            L(@"⚙️ [ACT] setSuccessView: %@", D(view));
            ((void (*)(id, SEL, id))orig)(self, @selector(setSuccessView:), view);
        }));
        L(@"  ✅ setSuccessView:");
    }

    // 8. setErrorLabel: —— 只记录
    m = class_getInstanceMethod(cls, @selector(setErrorLabel:));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id label) {
            L(@"⚙️ [ACT] setErrorLabel: %@", D(label));
            ((void (*)(id, SEL, id))orig)(self, @selector(setErrorLabel:), label);
        }));
        L(@"  ✅ setErrorLabel:");
    }

    // 9. setOnVerify: —— 只记录（关键！）
    m = class_getInstanceMethod(cls, @selector(setOnVerify:));
    if (m) {
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id block) {
            L(@"🔑 [ACT] setOnVerify: %@", D(block));
            ((void (*)(id, SEL, id))orig)(self, @selector(setOnVerify:), block);
        }));
        L(@"  ✅ setOnVerify:");
    }

    // 10. isActivated -> YES（唯一干预）
    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) { method_setImplementation(m, imp_implementationWithBlock(^(id self){ return YES; })); L(@"  ✅ isActivated->YES"); }

    // 11. isVerified -> YES（唯一干预）
    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) { method_setImplementation(m, imp_implementationWithBlock(^(id self){ return YES; })); L(@"  ✅ isVerified->YES"); }
}

// ============================================================
// 🔍 系统级观察 hook（延迟安装）
// ============================================================
static void (*o_vdl)(id,SEL);
static void d_vdl(id self, SEL _cmd) {
    NSString *cls = NSStringFromClass([self class]);
    if (![cls hasPrefix:@"UI"] && ![cls hasPrefix:@"NS"] && ![cls hasPrefix:@"_UI"]) {
        L(@"📱 [SYS] viewDidLoad → %@", cls);
    }
    o_vdl(self,_cmd);
}
static void (*o_push)(id,SEL,id,BOOL);
static void d_push(id self, SEL _cmd, id vc, BOOL a) {
    L(@"📱 [SYS] push %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc class]));
    o_push(self,_cmd,vc,a);
}
static void (*o_pre)(id,SEL,id,BOOL,id);
static void d_pre(id self, SEL _cmd, id vc, BOOL a, id c) {
    L(@"📱 [SYS] present %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc class]));
    o_pre(self,_cmd,vc,a,c);
}
static void (*o_rd)(id,SEL);
static void d_rd(id self, SEL _cmd) {
    @try {
        NSInteger sec=[(UITableView*)self numberOfSections], rows=0;
        for(NSInteger i=0;i<sec;i++)rows+=[(UITableView*)self numberOfRowsInSection:i];
        L(@"📋 [SYS] reloadData %@ sec=%ld rows=%ld", NSStringFromClass([self class]),(long)sec,(long)rows);
    } @catch(NSException*e){}
    o_rd(self,_cmd);
}
static id (*o_ug)(id,SEL,id);
static id d_ug(id self, SEL _cmd, id k) {
    id v=o_ug(self,_cmd,k);
    // 只记录包含 kfun/activation/token/expire 等关键 key
    NSString *ks = [k lowercaseString];
    if ([ks containsString:@"kfun"] || [ks containsString:@"activ"] || [ks containsString:@"token"] || [ks containsString:@"expire"] || [ks containsString:@"auth"] || [ks containsString:@"license"] || [ks containsString:@"verify"]) {
        L(@"💾 [UD] read %@ = %@", k, D(v));
    }
    return v;
}
static void (*o_us)(id,SEL,id,id);
static void d_us(id self, SEL _cmd, id v, id k) {
    NSString *ks = [k lowercaseString];
    if ([ks containsString:@"kfun"] || [ks containsString:@"activ"] || [ks containsString:@"token"] || [ks containsString:@"expire"] || [ks containsString:@"auth"] || [ks containsString:@"license"] || [ks containsString:@"verify"]) {
        L(@"💾 [UD] write %@ = %@", k, D(v));
    }
    o_us(self,_cmd,v,k);
}
static NSURLSessionDataTask* (*o_surl)(id,SEL,id,id);
static NSURLSessionDataTask* d_surl(id self, SEL _cmd, id url, id cb) {
    L(@"🌐 [NET] GET %@", [url absoluteString]);
    void(^ocb)(NSData*,NSURLResponse*,NSError*) = cb;
    void(^w)(NSData*,NSURLResponse*,NSError*) = ^(NSData*d,NSURLResponse*r,NSError*e){
        @try {
            NSHTTPURLResponse *h=[r isKindOfClass:[NSHTTPURLResponse class]]?(NSHTTPURLResponse*)r:nil;
            L(@"🌐 [NET] RESP %@ st=%ld len=%lu err=%@", [url absoluteString], (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0), e?e.localizedDescription:@"none");
            if(d&&d.length<512){NSString*b=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]; if(b)L(@"🌐 BODY:%@",b);}
        } @catch(NSException*ex){}
        if(ocb)ocb(d,r,e);
    };
    return o_surl(self,_cmd,url,w);
}
static NSURLSessionDataTask* (*o_sreq)(id,SEL,id,id);
static NSURLSessionDataTask* d_sreq(id self, SEL _cmd, id req, id cb) {
    NSURLRequest *r=req;
    L(@"🌐 [NET] %@ %@", r.HTTPMethod, r.URL.absoluteString);
    if(r.HTTPBody&&r.HTTPBody.length<256){NSString*b=[[NSString alloc]initWithData:r.HTTPBody encoding:NSUTF8StringEncoding]; if(b)L(@"🌐 REQBODY:%@",b);}
    void(^ocb)(NSData*,NSURLResponse*,NSError*) = cb;
    void(^w)(NSData*,NSURLResponse*,NSError*) = ^(NSData*d,NSURLResponse*resp,NSError*e){
        @try {
            NSHTTPURLResponse *h=[resp isKindOfClass:[NSHTTPURLResponse class]]?(NSHTTPURLResponse*)resp:nil;
            L(@"🌐 [NET] RESP %@ st=%ld len=%lu", r.URL.absoluteString, (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0));
            if(d&&d.length<512){NSString*b=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]; if(b)L(@"🌐 BODY:%@",b);}
        } @catch(NSException*ex){}
        if(ocb)ocb(d,resp,e);
    };
    return o_sreq(self,_cmd,req,w);
}

static void installSysHooks() {
    L(@"🔧 安装系统观察hook...");
    @try { Method m=class_getInstanceMethod([UIViewController class],@selector(viewDidLoad)); if(m){o_vdl=(void(*)(id,SEL))method_getImplementation(m); method_setImplementation(m,(IMP)d_vdl);} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([UINavigationController class],@selector(pushViewController:animated:)); if(m){o_push=(void(*)(id,SEL,id,BOOL))method_getImplementation(m); method_setImplementation(m,(IMP)d_push);} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([UIViewController class],@selector(presentViewController:animated:completion:)); if(m){o_pre=(void(*)(id,SEL,id,BOOL,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_pre);} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([UITableView class],@selector(reloadData)); if(m){o_rd=(void(*)(id,SEL))method_getImplementation(m); method_setImplementation(m,(IMP)d_rd);} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([NSUserDefaults class],@selector(objectForKey:)); if(m){o_ug=(id(*)(id,SEL,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_ug);} m=class_getInstanceMethod([NSUserDefaults class],@selector(setObject:forKey:)); if(m){o_us=(void(*)(id,SEL,id,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_us);} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([NSURLSession class],@selector(dataTaskWithURL:completionHandler:)); if(m){o_surl=(NSURLSessionDataTask*(*)(id,SEL,id,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_surl);} m=class_getInstanceMethod([NSURLSession class],@selector(dataTaskWithRequest:completionHandler:)); if(m){o_sreq=(NSURLSessionDataTask*(*)(id,SEL,id,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_sreq);} } @catch(NSException*e){}
    L(@"🔧 系统hook完成");
}

// ============================================================
// 🔄 轮询 —— 观察当前界面完整结构
// ============================================================
static void poll() {
    [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *t) {
        @try {
            UIViewController *vc = topVC();
            if (!vc) return;
            NSString *cls = NSStringFromClass([vc class]);
            L(@"📍 当前顶层: %@", cls);

            if ([vc isKindOfClass:[UITabBarController class]]) {
                L(@"📍 TabBar 结构:");
                UITabBarController *tbc = (UITabBarController*)vc;
                for (NSInteger i=0; i<tbc.viewControllers.count; i++) {
                    L(@"  📁 Tab[%ld]:", (long)i);
                    dumpVC(tbc.viewControllers[i], @"    ");
                }
            } else if ([vc isKindOfClass:[objc_getClass("WWWActivationViewController") class]]) {
                dumpVC(vc, @"  ");
            }
        } @catch (NSException *e) { L(@"❌ poll: %@", e.reason); }
    }];
    L(@"🔄 轮询已启动");
}

__attribute__((constructor))
static void init() {
    NSLog(@"========================================");
    NSLog(@"[K8] KFun观察v8已加载");
    NSLog(@"========================================");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWin();
        Class cc = [UIControl class];
        Method m = class_getInstanceMethod(cc, @selector(sendAction:to:forEvent:));
        if (m) { orig_send = (void(*)(id,SEL,SEL,id,id))method_getImplementation(m); method_setImplementation(m,(IMP)hook_send); L(@"✅ UIControl.sendAction"); }

        Class act = objc_getClass("WWWActivationViewController");
        if (act) {
            hookActMethods(act);
        } else {
            L(@"❌ 未找到 WWWActivationViewController");
        }

        poll();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ installSysHooks(); });

        L(@"🚀 初始化完成");
        L(@"💡 操作：输入15位假卡密 → 点验证 → 观察日志");
        L(@"💡 重点观察：showSuccess:completion: / setOnVerify: / dismiss");
    });
}
