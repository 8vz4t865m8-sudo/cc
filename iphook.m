//
//  KFun 诊断 Tweak v3 —— 修复闪退版
//  原则：只观察，不干预。绝不调用原始逻辑之外的代码。
//  编译：theos / iOSOpenDev
//  注入：kfun (seo.darksword-kexploitfff)
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>

#pragma mark - 悬浮窗

@interface KFWin : UIView
+ (instancetype)s;
- (void)log:(NSString *)msg;
@end

@implementation KFWin {
    UITextView *_tv;
    BOOL _exp;
}
+ (instancetype)s {
    static KFWin *w; static dispatch_once_t t;
    dispatch_once(&t, ^{ w = [[self alloc] init]; }); return w;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(4, 90, 360, 34)];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.95];
        self.layer.cornerRadius = 8;
        self.layer.borderColor = [UIColor cyanColor].CGColor;
        self.layer.borderWidth = 1;
        self.userInteractionEnabled = YES;

        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,360,32)];
        bar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
        [self addSubview:bar];

        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(6,4,220,24)];
        t.text = @"🔍 KFun诊断v3(点我展开)";
        t.textColor = [UIColor cyanColor];
        t.font = [UIFont boldSystemFontOfSize:10];
        [bar addSubview:t];

        UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
        cp.frame = CGRectMake(298,4,58,24);
        [cp setTitle:@"📋复制" forState:UIControlStateNormal];
        [cp setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        cp.titleLabel.font = [UIFont systemFontOfSize:9];
        [cp addTarget:self action:@selector(copyAll:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:cp];

        _tv = [[UITextView alloc] initWithFrame:CGRectMake(2,34,356,0)];
        _tv.textColor = [UIColor greenColor];
        _tv.font = [UIFont fontWithName:@"Menlo" size:8];
        _tv.backgroundColor = [UIColor clearColor];
        _tv.editable = NO;
        _tv.text = @"[系统] KFun诊断v3已启动\n";
        [self addSubview:_tv];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [bar addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        [bar addGestureRecognizer:tap];
        _exp = NO;
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)p {
    CGPoint tr = [p translationInView:self.superview];
    self.center = CGPointMake(self.center.x+tr.x, self.center.y+tr.y);
    [p setTranslation:CGPointZero inView:self.superview];
}
- (void)toggle {
    _exp = !_exp;
    [UIView animateWithDuration:0.2 animations:^{
        if (_exp) { self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 360, 440); _tv.frame = CGRectMake(2,34,356,404); }
        else { self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 360, 34); _tv.frame = CGRectMake(2,34,356,0); }
    }];
}
- (void)copyAll:(id)s {
    if (_tv.text.length) { UIPasteboard.generalPasteboard.string = _tv.text; [self log:@"📋 日志已复制"]; }
}
- (void)log:(NSString *)msg {
    NSLog(@"[KFD3] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *ts = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970];
        NSString *line = [NSString stringWithFormat:@"[%@] %@", ts, msg];
        NSString *nt = _tv.text.length ? [NSString stringWithFormat:@"%@\n%@", _tv.text, line] : line;
        if (nt.length > 12000) nt = [nt substringFromIndex:nt.length-12000];
        _tv.text = nt;
        [_tv scrollRangeToVisible:NSMakeRange(nt.length-1, 1)];
    });
}
- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
                if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene*)sc).activationState == UISceneActivationStateForegroundActive) {
                    kw = ((UIWindowScene*)sc).windows.firstObject; break;
                }
            }
        }
        if (!kw) kw = UIApplication.sharedApplication.windows.firstObject;
        if (kw && !self.superview) [kw addSubview:self];
    });
}
@end

static void KLog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    [[KFWin s] log:s];
}

#pragma mark - 安全 Swizzle 工具

static void kf_swizzle(Class cls, SEL orig, SEL repl) {
    Method om = class_getInstanceMethod(cls, orig);
    Method rm = class_getInstanceMethod(cls, repl);
    if (!om || !rm) return;
    method_exchangeImplementations(om, rm);
}

static NSString *kf_desc(id obj) {
    if (!obj) return @"nil";
    if ([obj isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"\"%@\"", obj];
    if ([obj isKindOfClass:[NSArray class]]) return [NSString stringWithFormat:@"NSArray(count=%lu)", (unsigned long)[(NSArray*)obj count]];
    if ([obj isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"NSDictionary(count=%lu keys=%@)", (unsigned long)[(NSDictionary*)obj count], [(NSDictionary*)obj allKeys]];
    if ([obj isKindOfClass:[NSData class]]) {
        NSData *d = obj;
        if (d.length < 256) {
            NSString *tryStr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (tryStr) return [NSString stringWithFormat:@"NSData(len=%lu,utf8=%@)", (unsigned long)d.length, tryStr];
        }
        return [NSString stringWithFormat:@"NSData(len=%lu)", (unsigned long)d.length];
    }
    return [obj description];
}

#pragma mark - 1. UIViewController 追踪（安全）

@interface UIViewController (KFD3)
@end
@implementation UIViewController (KFD3)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(viewDidLoad), @selector(kf_vdl));
        kf_swizzle(self, @selector(viewWillAppear:), @selector(kf_vwa:));
        kf_swizzle(self, @selector(viewDidAppear:), @selector(kf_vda:));
    });
}
- (void)kf_vdl {
    KLog(@"📱 [VC] viewDidLoad → %@", NSStringFromClass([self class]));
    [self kf_dump];
    [self kf_vdl];
}
- (void)kf_vwa:(BOOL)a { KLog(@"📱 [VC] viewWillAppear → %@", NSStringFromClass([self class])); [self kf_vwa:a]; }
- (void)kf_vda:(BOOL)a { KLog(@"📱 [VC] viewDidAppear → %@", NSStringFromClass([self class])); [self kf_vda:a]; }

- (void)kf_dump {
    // dump ivars
    unsigned int n=0;
    Ivar *iv = class_copyIvarList([self class], &n);
    for (unsigned int i=0; i<n; i++) {
        NSString *name = [NSString stringWithUTF8String:ivar_getName(iv[i])];
        if ([name hasPrefix:@"_"]) {
            @try {
                id v = object_getIvar(self, iv[i]);
                if (v) KLog(@"   🔒 %@.%@ = %@", NSStringFromClass([self class]), name, kf_desc(v));
            } @catch(NSException *e){}
        }
    }
    free(iv);
    // dump properties (只读值，不触发 setter)
    objc_property_t *ps = class_copyPropertyList([self class], &n);
    for (unsigned int i=0; i<n; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(ps[i])];
        if ([name isEqualToString:@"view"]) continue;
        @try {
            id v = [self valueForKey:name];
            if (v) KLog(@"   📦 %@.%@ = %@", NSStringFromClass([self class]), name, kf_desc(v));
        } @catch(NSException *e){}
    }
    free(ps);
}
@end

#pragma mark - 2. UINavigationController push 追踪

@interface UINavigationController (KFD3)
@end
@implementation UINavigationController (KFD3)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ kf_swizzle(self, @selector(pushViewController:animated:), @selector(kf_push:ani:)); });
}
- (void)kf_push:(UIViewController*)vc ani:(BOOL)a {
    KLog(@"📱 [NAV] push %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc class]));
    [self kf_push:vc ani:a];
}
@end

#pragma mark - 3. present 追踪

@interface UIViewController (KFD3Present)
@end
@implementation UIViewController (KFD3Present)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ kf_swizzle(self, @selector(presentViewController:animated:completion:), @selector(kf_pre:ani:comp:)); });
}
- (void)kf_pre:(UIViewController*)vc ani:(BOOL)a comp:(void(^)(void))c {
    KLog(@"📱 [VC] present %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc class]));
    [self kf_pre:vc ani:a comp:c];
}
@end

#pragma mark - 4. 按钮点击追踪

@interface UIControl (KFD3)
@end
@implementation UIControl (KFD3)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ kf_swizzle(self, @selector(sendAction:to:forEvent:), @selector(kf_send:to:forEvent:)); });
}
- (void)kf_send:(SEL)action to:(id)target forEvent:(UIEvent*)event {
    NSString *act = NSStringFromSelector(action);
    NSString *tgt = target ? NSStringFromClass([target class]) : @"nil";
    KLog(@"🖱️ [BTN] %@ → %@.%@", NSStringFromClass([self class]), tgt, act);
    if ([self isKindOfClass:[UIButton class]]) {
        NSString *tt = [((UIButton*)self) titleForState:UIControlStateNormal];
        if (tt.length) KLog(@"   └─ title=\"%@\"", tt);
    }
    [self kf_send:action to:target forEvent:event];
}
@end

#pragma mark - 5. TableView reloadData 追踪

@interface UITableView (KFD3)
@end
@implementation UITableView (KFD3)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ kf_swizzle(self, @selector(reloadData), @selector(kf_rd)); });
}
- (void)kf_rd {
    NSInteger sec = [self numberOfSections];
    NSInteger rows = 0;
    for (NSInteger i=0; i<sec; i++) rows += [self numberOfRowsInSection:i];
    KLog(@"📋 [TV] reloadData %@ | sections=%ld | totalRows=%ld", NSStringFromClass([self class]), (long)sec, (long)rows);
    [self kf_rd];
}
@end

#pragma mark - 6. NSUserDefaults 追踪

@interface NSUserDefaults (KFD3)
@end
@implementation NSUserDefaults (KFD3)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(objectForKey:), @selector(kf_get:));
        kf_swizzle(self, @selector(setObject:forKey:), @selector(kf_set:forKey:));
    });
}
- (id)kf_get:(NSString*)k { id v = [self kf_get:k]; KLog(@"💾 [UD] read %@ = %@", k, kf_desc(v)); return v; }
- (void)kf_set:(id)v forKey:(NSString*)k { KLog(@"💾 [UD] write %@ = %@", k, kf_desc(v)); [self kf_set:v forKey:k]; }
@end

#pragma mark - 7. 文件读写追踪

@interface NSData (KFD3)
@end
@implementation NSData (KFD3)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(writeToFile:atomically:), @selector(kf_wf:atom:));
        kf_swizzle(self, @selector(writeToFile:options:error:), @selector(kf_wf2:opt:err:));
    });
}
- (BOOL)kf_wf:(NSString*)p atom:(BOOL)a { KLog(@"💾 [FILE] write %@ | len=%lu", p, (unsigned long)self.length); return [self kf_wf:p atom:a]; }
- (BOOL)kf_wf2:(NSString*)p opt:(NSDataWritingOptions)o err:(NSError**)e { KLog(@"💾 [FILE] write %@ | len=%lu", p, (unsigned long)self.length); return [self kf_wf2:p opt:o err:e]; }
@end

@interface NSString (KFD3)
@end
@implementation NSString (KFD3)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ kf_swizzle(self, @selector(writeToFile:atomically:encoding:error:), @selector(kf_wf:atom:enc:err:)); });
}
- (BOOL)kf_wf:(NSString*)p atom:(BOOL)a enc:(NSStringEncoding)e err:(NSError**)er { KLog(@"💾 [FILE] writeStr %@ | content=%@", p, self); return [self kf_wf:p atom:a enc:e err:er]; }
@end

#pragma mark - 8. NSURLSession 追踪（系统层）

@interface NSURLSession (KFD3)
@end
@implementation NSURLSession (KFD3)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(dataTaskWithURL:completionHandler:), @selector(kf_dtURL:comp:));
        kf_swizzle(self, @selector(dataTaskWithRequest:completionHandler:), @selector(kf_dtReq:comp:));
    });
}
- (NSURLSessionDataTask*)kf_dtURL:(NSURL*)url comp:(void(^)(NSData*,NSURLResponse*,NSError*))cb {
    KLog(@"🌐 [NET] GET %@", url.absoluteString);
    void(^wrap)(NSData*,NSURLResponse*,NSError*) = ^(NSData*d,NSURLResponse*r,NSError*e){
        NSHTTPURLResponse *h = [r isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)r : nil;
        KLog(@"🌐 [NET] RESP %@ | status=%ld | len=%lu | err=%@", url.absoluteString, (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0), e?e.localizedDescription:@"none");
        if (d && d.length < 512) {
            NSString *b = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (b) KLog(@"🌐 [NET] BODY: %@", b);
        }
        if (cb) cb(d,r,e);
    };
    return [self kf_dtURL:url comp:wrap];
}
- (NSURLSessionDataTask*)kf_dtReq:(NSURLRequest*)req comp:(void(^)(NSData*,NSURLResponse*,NSError*))cb {
    KLog(@"🌐 [NET] %@ %@ | hdr=%@ | bodyLen=%lu", req.HTTPMethod, req.URL.absoluteString, req.allHTTPHeaderFields, (unsigned long)(req.HTTPBody?req.HTTPBody.length:0));
    if (req.HTTPBody && req.HTTPBody.length < 256) {
        NSString *b = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
        if (b) KLog(@"🌐 [NET] REQBODY: %@", b);
    }
    void(^wrap)(NSData*,NSURLResponse*,NSError*) = ^(NSData*d,NSURLResponse*r,NSError*e){
        NSHTTPURLResponse *h = [r isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)r : nil;
        KLog(@"🌐 [NET] RESP %@ | status=%ld | len=%lu", req.URL.absoluteString, (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0));
        if (d && d.length < 512) {
            NSString *b = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (b) KLog(@"🌐 [NET] BODY: %@", b);
        }
        if (cb) cb(d,r,e);
    };
    return [self kf_dtReq:req comp:wrap];
}
@end

#pragma mark - 9. 类扫描（只扫描，不 hook 方法）

static void kf_scanClasses() {
    int num = objc_getClassList(NULL, 0);
    Class *list = (Class*)malloc(sizeof(Class)*num);
    objc_getClassList(list, num);
    NSMutableArray *found = [NSMutableArray array];
    for (int i=0; i<num; i++) {
        NSString *n = NSStringFromClass(list[i]);
        if ([n hasPrefix:@"NS"] || [n hasPrefix:@"UI"] || [n hasPrefix:@"CA"] || [n hasPrefix:@"CG"]
            || [n hasPrefix:@"AV"] || [n hasPrefix:@"WK"] || [n hasPrefix:@"CL"] || [n hasPrefix:@"MK"]
            || [n hasPrefix:@"SC"] || [n hasPrefix:@"PK"] || [n hasPrefix:@"CN"] || [n hasPrefix:@"SL"]
            || [n hasPrefix:@"CI"] || [n hasPrefix:@"GL"] || [n hasPrefix:@"MTL"] || [n hasPrefix:@"IO"]
            || [n hasPrefix:@"OS_"] || [n hasPrefix:@"CF"] || [n hasPrefix:@"CT"] || [n hasPrefix:@"CV"]
            || [n hasPrefix:@"CM"] || [n hasPrefix:@"MF"] || [n hasPrefix:@"MP"] || [n hasPrefix:@"PH"]
            || [n hasPrefix:@"QL"] || [n hasPrefix:@"SF"] || [n hasPrefix:@"SS"] || [n hasPrefix:@"TI"]
            || [n hasPrefix:@"TX"] || [n hasPrefix:@"VS"] || [n hasPrefix:@"XC"]) continue;
        if ([n length] < 3 || [n hasPrefix:@"_"]) continue;
        if ([n rangeOfString:@"ViewController"].location != NSNotFound
            || [n rangeOfString:@"Manager"].location != NSNotFound
            || [n rangeOfString:@"Service"].location != NSNotFound
            || [n rangeOfString:@"Client"].location != NSNotFound
            || [n rangeOfString:@"Helper"].location != NSNotFound
            || [n rangeOfString:@"Config"].location != NSNotFound
            || [n rangeOfString:@"Data"].location != NSNotFound
            || [n rangeOfString:@"Model"].location != NSNotFound
            || [n rangeOfString:@"Cell"].location != NSNotFound
            || [n rangeOfString:@"Inject"].location != NSNotFound
            || [n rangeOfString:@"Aim"].location != NSNotFound
            || [n rangeOfString:@"Game"].location != NSNotFound
            || [n rangeOfString:@"Mem"].location != NSNotFound
            || [n rangeOfString:@"Read"].location != NSNotFound
            || [n rangeOfString:@"Pointer"].location != NSNotFound
            || [n rangeOfString:@"Bypass"].location != NSNotFound
            || [n rangeOfString:@"Sandbox"].location != NSNotFound
            || [n rangeOfString:@"Radar"].location != NSNotFound) {
            [found addObject:n];
        }
    }
    free(list);
    KLog(@"📊 扫描到 %lu 个重点自定义类", (unsigned long)found.count);
    for (NSString *n in found) {
        // 只打印类名和方法列表，不 hook
        Class cls = objc_getClass([n UTF8String]);
        if (!cls) continue;
        unsigned int mc = 0;
        Method *ms = class_copyMethodList(cls, &mc);
        NSMutableArray *methods = [NSMutableArray array];
        for (unsigned int i=0; i<mc; i++) {
            NSString *selName = NSStringFromSelector(method_getName(ms[i]));
            [methods addObject:selName];
        }
        free(ms);
        KLog(@"   📌 %@ | methods=%lu | %@", n, (unsigned long)methods.count, methods);
    }
}

#pragma mark - 入口

__attribute__((constructor))
static void kfd3_init() {
    NSLog(@"========================================");
    NSLog(@"[KFD3] KFun诊断v3已加载");
    NSLog(@"========================================");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[KFWin s] show];
        KLog(@"✅ 诊断悬浮窗就绪");
        KLog(@"📌 只观察，不干预。确保不闪退。");
        KLog(@"📌 操作：展开悬浮窗 → 正常操作App → 点击复制导出日志");
        kf_scanClasses();
    });
}
