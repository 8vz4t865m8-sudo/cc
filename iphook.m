//
//  KFun 诊断 Tweak v5 —— 策略调整版
//  核心：不hook onTapVerify，hook activateCode:completion: 并探测completion参数
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static UITextView *g_tv = nil;
static UIView *g_container = nil;
static BOOL g_clicked = NO;

static void L(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    NSLog(@"[K5] %@", s);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_tv) {
            NSString *t = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970];
            NSString *line = [NSString stringWithFormat:@"[%@] %@", t, s];
            NSString *nt = g_tv.text.length ? [NSString stringWithFormat:@"%@\n%@", g_tv.text, line] : line;
            if (nt.length > 12000) nt = [nt substringFromIndex:nt.length-12000];
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

        CGFloat w=340, h=340;
        g_container = [[UIView alloc] initWithFrame:CGRectMake(10,120,w,h)];
        g_container.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
        g_container.layer.cornerRadius = 10;
        g_container.layer.borderColor = [UIColor greenColor].CGColor;
        g_container.layer.borderWidth = 1.5;

        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,30)];
        bar.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
        [g_container addSubview:bar];

        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(8,4,w-70,22)];
        tl.text = @"🔍 KFun诊断v5(拖动/点展开)";
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
        g_tv.text = @"[系统] KFun诊断v5已启动\n💡 请手动点击验证按钮！\n💡 观察completion探测结果\n";
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

static void (*orig_send)(id, SEL, SEL, id, id);
static void hook_send(id self, SEL _cmd, SEL action, id target, UIEvent *event) {
    if ([self isKindOfClass:[UIButton class]]) {
        NSString *act = NSStringFromSelector(action);
        NSString *tgt = target ? NSStringFromClass([target class]) : @"nil";
        L(@"🖱️ BTN %@ -> %@.%@", NSStringFromClass([self class]), tgt, act);
        NSString *tt = [((UIButton*)self) titleForState:UIControlStateNormal];
        if (tt.length) L(@"   title=\"%@\"", tt);
        if ([act isEqualToString:@"onTapVerify"]) g_clicked = YES;
    }
    orig_send(self, _cmd, action, target, event);
}

static void liteBypass(id target) {
    L(@"🚀 LiteBypass...");
    @try {
        if ([target isKindOfClass:[UIViewController class]]) {
            for (UIView *v in ((UIViewController*)target).view.subviews) {
                if ([v isKindOfClass:[UIActivityIndicatorView class]]) { [(UIActivityIndicatorView*)v stopAnimating]; v.hidden = YES; }
            }
        }
    } @catch (NSException *e) {}
    L(@"✅ 转圈已停止");
    @try {
        id mask = [target valueForKey:@"authMaskView"];
        if (mask && [mask isKindOfClass:[UIView class]]) { [(UIView*)mask setHidden:YES]; [(UIView*)mask removeFromSuperview]; L(@"✅ mask已移除"); }
    } @catch (NSException *e) {}
}

static void tryCB(id completion) {
    if (!completion) { L(@"⚠️ completion=nil"); return; }
    L(@"🔬 探测completion参数格式...");
    NSDictionary *fd = @{@"status":@1, @"code":@200, @"msg":@"success", @"expire":@"2099-12-31", @"host":@"127.0.0.1:8080", @"values":@[@"突破沙盒",@"读取内存"], @"token":@"fake"};
    NSString *fs = @"{\"status\":1,\"expire\":\"2099-12-31\"}";

    @try { void(^cb)(NSDictionary*,NSError*) = completion; cb(fd, nil); L(@"✅ 2参数 (NSDictionary*,NSError*)"); return; } @catch (NSException *e) { L(@"❌ 2参数Dict: %@", e.reason); }
    @try { void(^cb)(BOOL,NSString*) = completion; cb(YES, @"success"); L(@"✅ 2参数 (BOOL,NSString*)"); return; } @catch (NSException *e) { L(@"❌ 2参数Bool: %@", e.reason); }
    @try { void(^cb)(NSDictionary*) = completion; cb(fd); L(@"✅ 1参数 NSDictionary*"); return; } @catch (NSException *e) { L(@"❌ 1参数Dict: %@", e.reason); }
    @try { void(^cb)(NSString*) = completion; cb(fs); L(@"✅ 1参数 NSString*"); return; } @catch (NSException *e) { L(@"❌ 1参数Str: %@", e.reason); }
    @try { void(^cb)(BOOL) = completion; cb(YES); L(@"✅ 1参数 BOOL"); return; } @catch (NSException *e) { L(@"❌ 1参数Bool: %@", e.reason); }
    @try { void(^cb)(NSNumber*) = completion; cb(@1); L(@"✅ 1参数 NSNumber*"); return; } @catch (NSException *e) { L(@"❌ 1参数Num: %@", e.reason); }
    @try { void(^cb)(id) = completion; cb(fd); L(@"✅ 1参数 id"); return; } @catch (NSException *e) { L(@"❌ 1参数id: %@", e.reason); }
    @try { void(^cb)(void) = completion; cb(); L(@"✅ 无参数"); return; } @catch (NSException *e) { L(@"❌ 无参数: %@", e.reason); }
    L(@"❌ 所有格式均失败");
}

static void hookActClass(Class cls) {
    if (!cls) return;
    L(@"🎣 Hook类: %s", class_getName(cls));
    Method m;

    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self) {
            L(@"🎯 viewDidLoad");
            struct objc_super s = {self, class_getSuperclass(object_getClass(self))};
            ((void (*)(struct objc_super*,SEL))objc_msgSendSuper)(&s, @selector(viewDidLoad));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!g_clicked) {
                    UIViewController *t = topVC();
                    if ([t isKindOfClass:[objc_getClass("WWWActivationViewController") class]]) { L(@"⏰ 8秒超时，LiteBypass"); liteBypass(t); }
                    else { L(@"⏰ 8秒超时，验证界面已关闭"); }
                } else { L(@"⏰ 8秒超时，用户已点击，跳过"); }
            });
        }));
        L(@"  ✅ viewDidLoad(8秒延迟)");
    }

    // 不hook onTapVerify！
    L(@"  ⏭️ onTapVerify未hook");

    m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *code, id completion) {
            g_clicked = YES;
            L(@"🎯 [ACTIVATE] code=\"%@\"", code);
            L(@"   completion=%@ class=%@", D(completion), NSStringFromClass([completion class]));
            L(@"   🚫 跳过网络请求");
            tryCB(completion);
            liteBypass(self);
        }));
        L(@"  ✅ activateCode:completion:");
    } else { L(@"  ⚠️ 无activateCode:"); }

    m = class_getInstanceMethod(cls, @selector(showError:));
    if (m) {
        method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *msg) {
            L(@"🛡️ showError: %@", msg); liteBypass(self);
        }));
        L(@"  ✅ showError:");
    }

    m = class_getInstanceMethod(cls, @selector(isActivated));
    if (m) { method_setImplementation(m, imp_implementationWithBlock(^(id self){ return YES; })); L(@"  ✅ isActivated->YES"); }

    m = class_getInstanceMethod(cls, @selector(isVerified));
    if (m) { method_setImplementation(m, imp_implementationWithBlock(^(id self){ return YES; })); L(@"  ✅ isVerified->YES"); }
}

static void scan() {
    L(@"🔍 扫描验证类...");
    Class c = objc_getClass("WWWActivationViewController");
    if (!c) c = objc_getClass("WWWActivation");
    if (c) hookActClass(c); else L(@"❌ 未找到验证类");
}

static void poll() {
    [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *t) {
        @try {
            UIViewController *vc = topVC();
            if (!vc) { L(@"⚠️ 无VC"); return; }
            L(@"📍 当前: %@", NSStringFromClass([vc class]));
            for (NSString *k in @[@"authMaskView",@"codeField",@"verifyButton",@"errorLabel",@"successView",@"spinner",@"tableView",@"values",@"host",@"dataText"]) {
                id v = nil; @try { v = [vc valueForKey:k]; } @catch (NSException *e) {}
                if (v) L(@"  📌 %@: %@", k, D(v));
            }
        } @catch (NSException *e) { L(@"❌ poll: %@", e.reason); }
    }];
    L(@"🔄 轮询已启动");
}

// 诊断hooks
static void (*o_vdl)(id,SEL);
static void d_vdl(id self, SEL _cmd) { L(@"📱 [VC] vdl %@", NSStringFromClass([self class])); o_vdl(self,_cmd); }
static void (*o_push)(id,SEL,id,BOOL);
static void d_push(id self, SEL _cmd, id vc, BOOL a) { L(@"📱 [NAV] push %@→%@", NSStringFromClass([self class]), NSStringFromClass([vc class])); o_push(self,_cmd,vc,a); }
static void (*o_pre)(id,SEL,id,BOOL,id);
static void d_pre(id self, SEL _cmd, id vc, BOOL a, id c) { L(@"📱 [VC] pre %@→%@", NSStringFromClass([self class]), NSStringFromClass([vc class])); o_pre(self,_cmd,vc,a,c); }
static void (*o_rd)(id,SEL);
static void d_rd(id self, SEL _cmd) {
    @try { NSInteger sec=[(UITableView*)self numberOfSections], rows=0; for(NSInteger i=0;i<sec;i++)rows+=[(UITableView*)self numberOfRowsInSection:i]; L(@"📋 [TV] rd %@ sec=%ld rows=%ld", NSStringFromClass([self class]),(long)sec,(long)rows); } @catch(NSException*e){}
    o_rd(self,_cmd);
}
static id (*o_ug)(id,SEL,id);
static id d_ug(id self, SEL _cmd, id k) { id v=o_ug(self,_cmd,k); L(@"💾 [UD] r %@=%@", k, D(v)); return v; }
static void (*o_us)(id,SEL,id,id);
static void d_us(id self, SEL _cmd, id v, id k) { L(@"💾 [UD] w %@=%@", k, D(v)); o_us(self,_cmd,v,k); }
static BOOL (*o_dwf)(id,SEL,id,BOOL);
static BOOL d_dwf(id self, SEL _cmd, id p, BOOL a) { L(@"💾 [FILE] w %@ len=%lu", p, (unsigned long)[(NSData*)self length]); return o_dwf(self,_cmd,p,a); }
static BOOL (*o_swf)(id,SEL,id,BOOL,NSUInteger,id);
static BOOL d_swf(id self, SEL _cmd, id p, BOOL a, NSUInteger e, id er) { L(@"💾 [FILE] ws %@=%@", p, self); return o_swf(self,_cmd,p,a,e,er); }
static NSURLSessionDataTask* (*o_surl)(id,SEL,id,id);
static NSURLSessionDataTask* d_surl(id self, SEL _cmd, id url, id cb) {
    L(@"🌐 [NET] GET %@", [url absoluteString]);
    void(^ocb)(NSData*,NSURLResponse*,NSError*) = cb;
    void(^w)(NSData*,NSURLResponse*,NSError*) = ^(NSData*d,NSURLResponse*r,NSError*e){
        @try { NSHTTPURLResponse *h=[r isKindOfClass:[NSHTTPURLResponse class]]?(NSHTTPURLResponse*)r:nil; L(@"🌐 [NET] RESP %@ st=%ld len=%lu err=%@", [url absoluteString], (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0), e?e.localizedDescription:@"none"); if(d&&d.length<512){NSString*b=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]; if(b)L(@"🌐 BODY:%@",b);} } @catch(NSException*ex){}
        if(ocb)ocb(d,r,e);
    };
    return o_surl(self,_cmd,url,w);
}
static NSURLSessionDataTask* (*o_sreq)(id,SEL,id,id);
static NSURLSessionDataTask* d_sreq(id self, SEL _cmd, id req, id cb) {
    NSURLRequest *r=req;
    L(@"🌐 [NET] %@ %@ hdr=%@ bl=%lu", r.HTTPMethod, r.URL.absoluteString, r.allHTTPHeaderFields, (unsigned long)(r.HTTPBody?r.HTTPBody.length:0));
    if(r.HTTPBody&&r.HTTPBody.length<256){NSString*b=[[NSString alloc]initWithData:r.HTTPBody encoding:NSUTF8StringEncoding]; if(b)L(@"🌐 REQBODY:%@",b);}
    void(^ocb)(NSData*,NSURLResponse*,NSError*) = cb;
    void(^w)(NSData*,NSURLResponse*,NSError*) = ^(NSData*d,NSURLResponse*resp,NSError*e){
        @try { NSHTTPURLResponse *h=[resp isKindOfClass:[NSHTTPURLResponse class]]?(NSHTTPURLResponse*)resp:nil; L(@"🌐 [NET] RESP %@ st=%ld len=%lu", r.URL.absoluteString, (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0)); if(d&&d.length<512){NSString*b=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]; if(b)L(@"🌐 BODY:%@",b);} } @catch(NSException*ex){}
        if(ocb)ocb(d,resp,e);
    };
    return o_sreq(self,_cmd,req,w);
}

static void installDiag() {
    L(@"🔧 安装诊断hook...");
    @try { Method m=class_getInstanceMethod([UIViewController class],@selector(viewDidLoad)); if(m){o_vdl=(void(*)(id,SEL))method_getImplementation(m); method_setImplementation(m,(IMP)d_vdl); L(@"  ✅ VC.vdl");} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([UINavigationController class],@selector(pushViewController:animated:)); if(m){o_push=(void(*)(id,SEL,id,BOOL))method_getImplementation(m); method_setImplementation(m,(IMP)d_push); L(@"  ✅ NAV.push");} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([UIViewController class],@selector(presentViewController:animated:completion:)); if(m){o_pre=(void(*)(id,SEL,id,BOOL,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_pre); L(@"  ✅ VC.pre");} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([UITableView class],@selector(reloadData)); if(m){o_rd=(void(*)(id,SEL))method_getImplementation(m); method_setImplementation(m,(IMP)d_rd); L(@"  ✅ TV.rd");} } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([NSUserDefaults class],@selector(objectForKey:)); if(m){o_ug=(id(*)(id,SEL,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_ug);} m=class_getInstanceMethod([NSUserDefaults class],@selector(setObject:forKey:)); if(m){o_us=(void(*)(id,SEL,id,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_us);} L(@"  ✅ UD"); } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([NSData class],@selector(writeToFile:atomically:)); if(m){o_dwf=(BOOL(*)(id,SEL,id,BOOL))method_getImplementation(m); method_setImplementation(m,(IMP)d_dwf);} L(@"  ✅ DATA.wf"); } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([NSString class],@selector(writeToFile:atomically:encoding:error:)); if(m){o_swf=(BOOL(*)(id,SEL,id,BOOL,NSUInteger,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_swf);} L(@"  ✅ STR.wf"); } @catch(NSException*e){}
    @try { Method m=class_getInstanceMethod([NSURLSession class],@selector(dataTaskWithURL:completionHandler:)); if(m){o_surl=(NSURLSessionDataTask*(*)(id,SEL,id,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_surl);} m=class_getInstanceMethod([NSURLSession class],@selector(dataTaskWithRequest:completionHandler:)); if(m){o_sreq=(NSURLSessionDataTask*(*)(id,SEL,id,id))method_getImplementation(m); method_setImplementation(m,(IMP)d_sreq);} L(@"  ✅ NET"); } @catch(NSException*e){}
    L(@"🔧 诊断hook完成");
}

__attribute__((constructor))
static void init() {
    NSLog(@"========================================");
    NSLog(@"[K5] KFun诊断v5已加载");
    NSLog(@"========================================");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setupWin();
        Class cc = [UIControl class];
        Method m = class_getInstanceMethod(cc, @selector(sendAction:to:forEvent:));
        if (m) { orig_send = (void(*)(id,SEL,SEL,id,id))method_getImplementation(m); method_setImplementation(m,(IMP)hook_send); L(@"✅ UIControl.sendAction"); }
        scan();
        poll();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ installDiag(); });
        L(@"🚀 初始化完成");
        L(@"💡 请手动点击验证按钮！");
    });
}
