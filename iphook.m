//
//  KFun 全面诊断 Tweak v2.0 —— 不花钱版
//  用途：动态追踪 KFun 所有运行时行为，找出空白原因
//  编译：theos (iOSOpenDev)
//  注入目标：kfun (BundleID: seo.darksword-kexploitfff)
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sys/sysctl.h>

#pragma mark - 日志悬浮窗

@interface KFLogWindow : UIView
+ (instancetype)shared;
- (void)show;
- (void)log:(NSString *)msg;
@end

@implementation KFLogWindow {
    UITextView *_tv;
    BOOL _expanded;
    CGFloat _lastY;
}
+ (instancetype)shared {
    static KFLogWindow *w;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ w = [[self alloc] init]; });
    return w;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(4, 90, 362, 36)];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.96];
        self.layer.cornerRadius = 8;
        self.layer.borderColor = [UIColor colorWithRed:0 green:0.8 blue:1 alpha:1].CGColor;
        self.layer.borderWidth = 1.2;

        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,362,32)];
        bar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
        [self addSubview:bar];

        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(6,4,220,24)];
        t.text = @"🔍 KFun诊断v2(拖动/点击展开)";
        t.textColor = [UIColor colorWithRed:0 green:0.8 blue:1 alpha:1];
        t.font = [UIFont boldSystemFontOfSize:10];
        [bar addSubview:t];

        UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
        cp.frame = CGRectMake(300,4,58,24);
        [cp setTitle:@"📋复制" forState:UIControlStateNormal];
        [cp setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        cp.titleLabel.font = [UIFont systemFontOfSize:9];
        [cp addTarget:self action:@selector(copyAll:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:cp];

        _tv = [[UITextView alloc] initWithFrame:CGRectMake(2,34,358,0)];
        _tv.textColor = [UIColor greenColor];
        _tv.font = [UIFont fontWithName:@"Menlo" size:8];
        _tv.backgroundColor = [UIColor clearColor];
        _tv.editable = NO;
        _tv.text = @"[系统] KFun诊断已启动\n";
        [self addSubview:_tv];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [bar addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        [bar addGestureRecognizer:tap];
        _expanded = NO; _lastY = 90;
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)p {
    CGPoint tr = [p translationInView:self.superview];
    self.center = CGPointMake(self.center.x+tr.x, self.center.y+tr.y);
    _lastY = self.frame.origin.y;
    [p setTranslation:CGPointZero inView:self.superview];
}
- (void)toggle {
    _expanded = !_expanded;
    [UIView animateWithDuration:0.25 animations:^{
        if (_expanded) {
            self.frame = CGRectMake(self.frame.origin.x, _lastY, 362, 460);
            _tv.frame = CGRectMake(2,34,358,424);
        } else {
            self.frame = CGRectMake(self.frame.origin.x, _lastY, 362, 36);
            _tv.frame = CGRectMake(2,34,358,0);
        }
    }];
}
- (void)copyAll:(id)s {
    if (_tv.text.length) {
        UIPasteboard.generalPasteboard.string = _tv.text;
        [self log:@"📋 日志已复制"];
    }
}
- (void)log:(NSString *)msg {
    NSLog(@"[KFD] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *ts = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970];
        NSString *line = [NSString stringWithFormat:@"[%@] %@", ts, msg];
        NSString *nt = _tv.text.length ? [NSString stringWithFormat:@"%@\n%@", _tv.text, line] : line;
        if (nt.length > 15000) nt = [nt substringFromIndex:nt.length-15000];
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

static void KFLog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    [[KFLogWindow shared] log:s];
}

#pragma mark - 通用 Swizzle 工具

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
        if (d.length < 512) {
            NSString *tryStr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (tryStr) return [NSString stringWithFormat:@"NSData(len=%lu,utf8=%@)", (unsigned long)d.length, tryStr];
        }
        return [NSString stringWithFormat:@"NSData(len=%lu)", (unsigned long)d.length];
    }
    if ([obj isKindOfClass:[NSError class]]) return [NSString stringWithFormat:@"NSError(%@)", ((NSError*)obj).localizedDescription];
    return [obj description];
}

#pragma mark - 1. 全局 VC 追踪

@interface UIViewController (KFDiag2)
@end
@implementation UIViewController (KFDiag2)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(viewDidLoad), @selector(kf_vdl));
        kf_swizzle(self, @selector(viewWillAppear:), @selector(kf_vwa:));
        kf_swizzle(self, @selector(viewDidAppear:), @selector(kf_vda:));
        kf_swizzle(self, @selector(presentViewController:animated:completion:), @selector(kf_pre:ani:comp:));
    });
}
- (void)kf_vdl {
    KFLog(@"📱 [VC] viewDidLoad → %@", NSStringFromClass([self class]));
    [self kf_dumpIvars];
    [self kf_dumpProps];
    [self kf_vdl];
}
- (void)kf_vwa:(BOOL)a {
    KFLog(@"📱 [VC] viewWillAppear → %@", NSStringFromClass([self class]));
    [self kf_vwa:a];
}
- (void)kf_vda:(BOOL)a {
    KFLog(@"📱 [VC] viewDidAppear → %@", NSStringFromClass([self class]));
    [self kf_vda:a];
}
- (void)kf_pre:(UIViewController*)vc ani:(BOOL)a comp:(void(^)(void))c {
    KFLog(@"📱 [VC] present %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc class]));
    [self kf_pre:vc ani:a comp:c];
}
- (void)kf_dumpIvars {
    unsigned int n=0;
    Ivar *iv = class_copyIvarList([self class], &n);
    for (unsigned int i=0; i<n; i++) {
        NSString *name = [NSString stringWithUTF8String:ivar_getName(iv[i])];
        if ([name hasPrefix:@"_"]) {
            @try {
                id v = object_getIvar(self, iv[i]);
                if (v) KFLog(@"   🔒 ivar %@ = %@", name, kf_desc(v));
            } @catch(NSException *e){}
        }
    }
    free(iv);
}
- (void)kf_dumpProps {
    unsigned int n=0;
    objc_property_t *ps = class_copyPropertyList([self class], &n);
    for (unsigned int i=0; i<n; i++) {
        NSString *name = [NSString stringWithUTF8String:property_getName(ps[i])];
        if ([name isEqualToString:@"view"]) continue;
        @try {
            id v = [self valueForKey:name];
            if (v) KFLog(@"   📦 prop %@ = %@", name, kf_desc(v));
        } @catch(NSException *e){}
    }
    free(ps);
}
@end

#pragma mark - 2. UINavigationController push 追踪

@interface UINavigationController (KFDiag2)
@end
@implementation UINavigationController (KFDiag2)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ kf_swizzle(self, @selector(pushViewController:animated:), @selector(kf_push:ani:)); });
}
- (void)kf_push:(UIViewController*)vc ani:(BOOL)a {
    KFLog(@"📱 [NAV] push %@ → %@", NSStringFromClass([self class]), NSStringFromClass([vc class]));
    [vc kf_dumpIvars];
    [self kf_push:vc ani:a];
}
@end

#pragma mark - 3. 按钮点击追踪

@interface UIControl (KFDiag2)
@end
@implementation UIControl (KFDiag2)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ kf_swizzle(self, @selector(sendAction:to:forEvent:), @selector(kf_send:to:forEvent:)); });
}
- (void)kf_send:(SEL)action to:(id)target forEvent:(UIEvent*)event {
    NSString *cls = NSStringFromClass([self class]);
    NSString *act = NSStringFromSelector(action);
    NSString *tgt = target ? NSStringFromClass([target class]) : @"nil";
    KFLog(@"🖱️ [BTN] %@ → %@.%@", cls, tgt, act);
    if ([self isKindOfClass:[UIButton class]]) {
        NSString *tt = [((UIButton*)self) titleForState:UIControlStateNormal];
        if (tt.length) KFLog(@"   └─ title=\"%@\"", tt);
    }
    [self kf_send:action to:target forEvent:event];
}
@end

#pragma mark - 4. TableView 数据源追踪

@interface UITableView (KFDiag2)
@end
@implementation UITableView (KFDiag2)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ kf_swizzle(self, @selector(reloadData), @selector(kf_rd)); });
}
- (void)kf_rd {
    NSInteger sec = [self numberOfSections];
    NSInteger rows = 0;
    for (NSInteger i=0; i<sec; i++) rows += [self numberOfRowsInSection:i];
    KFLog(@"📋 [TV] reloadData %@ | sections=%ld | totalRows=%ld", NSStringFromClass([self class]), (long)sec, (long)rows);
    [self kf_rd];
}
@end

#pragma mark - 5. NSUserDefaults 追踪

@interface NSUserDefaults (KFDiag2)
@end
@implementation NSUserDefaults (KFDiag2)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(objectForKey:), @selector(kf_get:));
        kf_swizzle(self, @selector(setObject:forKey:), @selector(kf_set:forKey:));
        kf_swizzle(self, @selector(integerForKey:), @selector(kf_int:));
        kf_swizzle(self, @selector(setInteger:forKey:), @selector(kf_setInt:forKey:));
    });
}
- (id)kf_get:(NSString*)k {
    id v = [self kf_get:k];
    KFLog(@"💾 [UD] read %@ = %@", k, kf_desc(v));
    return v;
}
- (void)kf_set:(id)v forKey:(NSString*)k {
    KFLog(@"💾 [UD] write %@ = %@", k, kf_desc(v));
    [self kf_set:v forKey:k];
}
- (NSInteger)kf_int:(NSString*)k {
    NSInteger v = [self kf_int:k];
    KFLog(@"💾 [UD] readInt %@ = %ld", k, (long)v);
    return v;
}
- (void)kf_setInt:(NSInteger)v forKey:(NSString*)k {
    KFLog(@"💾 [UD] writeInt %@ = %ld", k, (long)v);
    [self kf_setInt:v forKey:k];
}
@end

#pragma mark - 6. 文件读写追踪

@interface NSData (KFDiag2)
@end
@implementation NSData (KFDiag2)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(writeToFile:atomically:), @selector(kf_wf:atom:));
        kf_swizzle(self, @selector(writeToFile:options:error:), @selector(kf_wf2:opt:err:));
        kf_swizzle(self, @selector(initWithContentsOfFile:), @selector(kf_initFile:));
    });
}
- (BOOL)kf_wf:(NSString*)p atom:(BOOL)a {
    KFLog(@"💾 [FILE] write %@ | len=%lu", p, (unsigned long)self.length);
    return [self kf_wf:p atom:a];
}
- (BOOL)kf_wf2:(NSString*)p opt:(NSDataWritingOptions)o err:(NSError**)e {
    KFLog(@"💾 [FILE] write %@ | len=%lu", p, (unsigned long)self.length);
    return [self kf_wf2:p opt:o err:e];
}
- (instancetype)kf_initFile:(NSString*)p {
    KFLog(@"💾 [FILE] read %@", p);
    return [self kf_initFile:p];
}
@end

@interface NSString (KFDiag2)
@end
@implementation NSString (KFDiag2)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(writeToFile:atomically:encoding:error:), @selector(kf_wf:atom:enc:err:));
        kf_swizzle(self, @selector(stringWithContentsOfFile:encoding:error:), @selector(kf_strFile:enc:err:));
    });
}
- (BOOL)kf_wf:(NSString*)p atom:(BOOL)a enc:(NSStringEncoding)e err:(NSError**)er {
    KFLog(@"💾 [FILE] writeStr %@ | content=%@", p, self);
    return [self kf_wf:p atom:a enc:e err:er];
}
+ (instancetype)kf_strFile:(NSString*)p enc:(NSStringEncoding)e err:(NSError**)er {
    KFLog(@"💾 [FILE] readStr %@", p);
    return [self kf_strFile:p enc:e err:er];
}
@end

#pragma mark - 7. NSURLSession 网络追踪（系统层）

@interface NSURLSession (KFDiag2)
@end
@implementation NSURLSession (KFDiag2)
+ (void)load {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kf_swizzle(self, @selector(dataTaskWithURL:completionHandler:), @selector(kf_dtURL:comp:));
        kf_swizzle(self, @selector(dataTaskWithRequest:completionHandler:), @selector(kf_dtReq:comp:));
    });
}
- (NSURLSessionDataTask*)kf_dtURL:(NSURL*)url comp:(void(^)(NSData*,NSURLResponse*,NSError*))cb {
    KFLog(@"🌐 [NET] GET %@", url.absoluteString);
    void(^wrap)(NSData*,NSURLResponse*,NSError*) = ^(NSData*d,NSURLResponse*r,NSError*e){
        NSHTTPURLResponse *h = [r isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)r : nil;
        KFLog(@"🌐 [NET] RESP %@ | status=%ld | len=%lu | err=%@", url.absoluteString, (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0), e?e.localizedDescription:@"none");
        if (d && d.length < 1024) {
            NSString *b = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (b) KFLog(@"🌐 [NET] BODY: %@", b);
        }
        if (cb) cb(d,r,e);
    };
    return [self kf_dtURL:url comp:wrap];
}
- (NSURLSessionDataTask*)kf_dtReq:(NSURLRequest*)req comp:(void(^)(NSData*,NSURLResponse*,NSError*))cb {
    KFLog(@"🌐 [NET] %@ %@ | hdr=%@ | bodyLen=%lu", req.HTTPMethod, req.URL.absoluteString, req.allHTTPHeaderFields, (unsigned long)(req.HTTPBody?req.HTTPBody.length:0));
    if (req.HTTPBody && req.HTTPBody.length < 512) {
        NSString *b = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
        if (b) KFLog(@"🌐 [NET] REQBODY: %@", b);
    }
    void(^wrap)(NSData*,NSURLResponse*,NSError*) = ^(NSData*d,NSURLResponse*r,NSError*e){
        NSHTTPURLResponse *h = [r isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)r : nil;
        KFLog(@"🌐 [NET] RESP %@ | status=%ld | len=%lu", req.URL.absoluteString, (long)(h?h.statusCode:0), (unsigned long)(d?d.length:0));
        if (d && d.length < 1024) {
            NSString *b = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (b) KFLog(@"🌐 [NET] BODY: %@", b);
        }
        if (cb) cb(d,r,e);
    };
    return [self kf_dtReq:req comp:wrap];
}
@end

#pragma mark - 8. 暴力探测所有自定义类 + 关键方法

static void kf_hookClass(NSString *clsName) {
    Class cls = objc_getClass([clsName UTF8String]);
    if (!cls) return;

    unsigned int mc = 0;
    Method *ms = class_copyMethodList(cls, &mc);
    for (unsigned int i=0; i<mc; i++) {
        SEL sel = method_getName(ms[i]);
        NSString *name = NSStringFromSelector(sel);
        NSUInteger argc = method_getNumberOfArguments(ms[i]);

        // 只 hook 关键方法
        BOOL isKey = [name hasPrefix:@"set"] || [name hasPrefix:@"activate"] || [name hasPrefix:@"verify"]
                  || [name hasPrefix:@"setup"] || [name hasPrefix:@"build"] || [name hasPrefix:@"load"]
                  || [name hasPrefix:@"start"] || [name hasPrefix:@"stop"] || [name hasPrefix:@"read"]
                  || [name isEqualToString:@"init"] || [name isEqualToString:@"initWithFrame:"]
                  || [name isEqualToString:@"initWithStyle:reuseIdentifier:"]
                  || [name isEqualToString:@"initWithCoder:"];
        if (!isKey) continue;

        IMP orig = method_getImplementation(ms[i]);
        if (argc == 2) {
            id blk = ^(id self) {
                KFLog(@"🔧 [%@ %@] called", clsName, name);
                ((void(*)(id,SEL))orig)(self, sel);
            };
            method_setImplementation(ms[i], imp_implementationWithBlock(blk));
        } else if (argc == 3) {
            id blk = ^(id self, id arg) {
                KFLog(@"🔧 [%@ %@:%@] called", clsName, name, kf_desc(arg));
                ((void(*)(id,SEL,id))orig)(self, sel, arg);
            };
            method_setImplementation(ms[i], imp_implementationWithBlock(blk));
        } else if (argc == 4) {
            id blk = ^(id self, id a, id b) {
                KFLog(@"🔧 [%@ %@:%@ :%@] called", clsName, name, kf_desc(a), kf_desc(b));
                ((void(*)(id,SEL,id,id))orig)(self, sel, a, b);
            };
            method_setImplementation(ms[i], imp_implementationWithBlock(blk));
        }
    }
    free(ms);
}

static void kf_scanAllClasses() {
    int num = objc_getClassList(NULL, 0);
    Class *list = (Class*)malloc(sizeof(Class)*num);
    objc_getClassList(list, num);

    NSMutableArray *custom = [NSMutableArray array];
    for (int i=0; i<num; i++) {
        NSString *n = NSStringFromClass(list[i]);
        // 排除系统类
        if ([n hasPrefix:@"NS"] || [n hasPrefix:@"UI"] || [n hasPrefix:@"CA"] || [n hasPrefix:@"CG"]
            || [n hasPrefix:@"AV"] || [n hasPrefix:@"WK"] || [n hasPrefix:@"CL"] || [n hasPrefix:@"MK"]
            || [n hasPrefix:@"SC"] || [n hasPrefix:@"PK"] || [n hasPrefix:@"CN"] || [n hasPrefix:@"SL"]
            || [n hasPrefix:@"CI"] || [n hasPrefix:@"GL"] || [n hasPrefix:@"MTL"] || [n hasPrefix:@"IO"]
            || [n hasPrefix:@"OS_"] || [n hasPrefix:@"CF"] || [n hasPrefix:@"CT"] || [n hasPrefix:@"CV"]
            || [n hasPrefix:@"CM"] || [n hasPrefix:@"MF"] || [n hasPrefix:@"MP"] || [n hasPrefix:@"PH"]
            || [n hasPrefix:@"QL"] || [n hasPrefix:@"SF"] || [n hasPrefix:@"SS"] || [n hasPrefix:@"TI"]
            || [n hasPrefix:@"TX"] || [n hasPrefix:@"VS"] || [n hasPrefix:@"XC"] || [n hasPrefix:@"AB"]
            || [n hasPrefix:@"AC"] || [n hasPrefix:@"AD"] || [n hasPrefix:@"AE"] || [n hasPrefix:@"AF"]
            || [n hasPrefix:@"AG"] || [n hasPrefix:@"AH"] || [n hasPrefix:@"AI"] || [n hasPrefix:@"AJ"]
            || [n hasPrefix:@"AK"] || [n hasPrefix:@"AL"] || [n hasPrefix:@"AM"] || [n hasPrefix:@"AN"]
            || [n hasPrefix:@"AO"] || [n hasPrefix:@"AP"] || [n hasPrefix:@"AQ"] || [n hasPrefix:@"AR"]
            || [n hasPrefix:@"AS"] || [n hasPrefix:@"AT"] || [n hasPrefix:@"AU"]) continue;
        if ([n length] < 3 || [n hasPrefix:@"_"]) continue;

        // 重点类名
        if ([n rangeOfString:@"ViewController"].location != NSNotFound
            || [n rangeOfString:@"Manager"].location != NSNotFound
            || [n rangeOfString:@"Service"].location != NSNotFound
            || [n rangeOfString:@"Client"].location != NSNotFound
            || [n rangeOfString:@"Helper"].location != NSNotFound
            || [n rangeOfString:@"Config"].location != NSNotFound
            || [n rangeOfString:@"Data"].location != NSNotFound
            || [n rangeOfString:@"Model"].location != NSNotFound
            || [n rangeOfString:@"Cell"].location != NSNotFound
            || [n rangeOfString:@"Radar"].location != NSNotFound
            || [n rangeOfString:@"Inject"].location != NSNotFound
            || [n rangeOfString:@"Aim"].location != NSNotFound
            || [n rangeOfString:@"Game"].location != NSNotFound
            || [n rangeOfString:@"Mem"].location != NSNotFound
            || [n rangeOfString:@"Read"].location != NSNotFound
            || [n rangeOfString:@"Pointer"].location != NSNotFound
            || [n rangeOfString:@"Bypass"].location != NSNotFound
            || [n rangeOfString:@"Sandbox"].location != NSNotFound) {
            [custom addObject:n];
        }
    }
    free(list);

    KFLog(@"📊 发现 %lu 个重点自定义类", (unsigned long)custom.count);
    for (NSString *n in custom) {
        KFLog(@"   📌 %@", n);
        kf_hookClass(n);
    }
}

#pragma mark - 9. 特别 Hook：activateCode:completion: 回调探测

// 这个 block 拦截器会尝试打印和调用 block
static void kf_probeBlock(id block, NSString *ctx) {
    KFLog(@"🔬 [BLOCK] %@ | block=%@ | class=%@", ctx, block, NSStringFromClass([block class]));
    // 尝试获取 block 的签名（不保证成功）
    struct Block_layout {
        void *isa;
        int flags;
        int reserved;
        void (*invoke)(void *, ...);
        struct Block_descriptor {
            unsigned long int reserved;
            unsigned long int size;
            void *copy_helper;
            void *dispose_helper;
            const char *signature;
        } *descriptor;
    };
    struct Block_layout *bl = (__bridge struct Block_layout *)block;
    if (bl && bl->descriptor && bl->descriptor->signature) {
        NSString *sig = [NSString stringWithUTF8String:bl->descriptor->signature];
        KFLog(@"🔬 [BLOCK] signature=%@", sig);
    }
}

// 延迟 hook activateCode:completion:，因为类可能还没加载
static void kf_hookActivation() {
    Class cls = objc_getClass("WWWActivationViewController");
    if (!cls) {
        KFLog(@"⚠️ WWWActivationViewController 未找到，1秒后重试");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ kf_hookActivation(); });
        return;
    }

    Method m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (!m) {
        KFLog(@"⚠️ activateCode:completion: 方法未找到");
        return;
    }

    IMP orig = method_getImplementation(m);
    id blk = ^(id self, NSString *code, id completion) {
        KFLog(@"🎯 [ACTIVATE] activateCode:\"%@\" completion=%@", code, kf_desc(completion));
        kf_probeBlock(completion, @"activateCode completion");

        // 关键：我们不发网络请求，而是直接调用 completion 并传入假的成功响应
        // 先尝试 NSDictionary 作为参数（最常见）
        if (completion) {
            KFLog(@"🎯 [ACTIVATE] 尝试直接调用 completion...");
            // 构造假的成功响应
            NSDictionary *fakeResp = @{
                @"status": @1,
                @"msg": @"success",
                @"expire": @"2099-12-31",
                @"host": @"127.0.0.1:8080",
                @"values": @[@"突破沙盒", @"读取内存", @"自瞄开关"]
            };

            // 尝试多种 block 签名调用
            @try {
                // 尝试 (void)(^)(NSDictionary *)
                void (^cbDict)(NSDictionary*) = (void (^)(NSDictionary*))completion;
                cbDict(fakeResp);
                KFLog(@"✅ [ACTIVATE] completion 以 NSDictionary 参数调用成功");
            } @catch (NSException *e1) {
                KFLog(@"❌ [ACTIVATE] NSDictionary 参数调用失败: %@", e1.reason);
                @try {
                    // 尝试 (void)(^)(NSString *)
                    void (^cbStr)(NSString*) = (void (^)(NSString*))completion;
                    cbStr(@"success");
                    KFLog(@"✅ [ACTIVATE] completion 以 NSString 参数调用成功");
                } @catch (NSException *e2) {
                    KFLog(@"❌ [ACTIVATE] NSString 参数调用失败: %@", e2.reason);
                    @try {
                        // 尝试 (void)(^)(BOOL)
                        void (^cbBool)(BOOL) = (void (^)(BOOL))completion;
                        cbBool(YES);
                        KFLog(@"✅ [ACTIVATE] completion 以 BOOL 参数调用成功");
                    } @catch (NSException *e3) {
                        KFLog(@"❌ [ACTIVATE] BOOL 参数调用失败: %@", e3.reason);
                        @try {
                            // 尝试 (void)(^)(void)
                            void (^cbVoid)(void) = (void (^)(void))completion;
                            cbVoid();
                            KFLog(@"✅ [ACTIVATE] completion 以无参数调用成功");
                        } @catch (NSException *e4) {
                            KFLog(@"❌ [ACTIVATE] 无参数调用也失败: %@", e4.reason);
                        }
                    }
                }
            }
        }

        // 同时调用原始方法（让它也走一遍，看看会发生什么）
        // 注意：这里我们其实已经调用了 completion，原始方法再调用可能会重复
        // 但为了观察原始网络请求，我们还是调用原始方法
        ((void (*)(id, SEL, NSString*, id))orig)(self, @selector(activateCode:completion:), code, completion);
    };
    method_setImplementation(m, imp_implementationWithBlock(blk));
    KFLog(@"✅ activateCode:completion: 已 hook");
}

#pragma mark - 10. 特别 Hook：buildSuccessViewWithExpire:

static void kf_hookBuildSuccess() {
    Class cls = objc_getClass("WWWActivationViewController");
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(buildSuccessViewWithExpire:));
    if (!m) return;
    IMP orig = method_getImplementation(m);
    id blk = ^(id self, NSString *expire) {
        KFLog(@"🏆 [BUILD] buildSuccessViewWithExpire:\"%@\"", expire);
        ((void (*)(id, SEL, NSString*))orig)(self, @selector(buildSuccessViewWithExpire:), expire);
    };
    method_setImplementation(m, imp_implementationWithBlock(blk));
    KFLog(@"✅ buildSuccessViewWithExpire: 已 hook");
}

#pragma mark - 11. libcurl C函数 Hook（如果 substrate 可用）

// 尝试通过 dlsym 获取 libcurl 函数并 hook
static void (*orig_curl_easy_setopt)(void*, int, ...);
static int hooked_curl_easy_setopt(void *curl, int option, ...) {
    va_list args;
    va_start(args, option);
    if (option == 10002) { // CURLOPT_URL = 10002
        char *url = va_arg(args, char*);
        KFLog(@"🌐 [CURL] CURLOPT_URL = %s", url ? url : "(null)");
    } else if (option == 10015) { // CURLOPT_POSTFIELDS = 10015
        char *data = va_arg(args, char*);
        KFLog(@"🌐 [CURL] CURLOPT_POSTFIELDS = %s", data ? data : "(null)");
    } else if (option == 64) { // CURLOPT_SSL_VERIFYPEER = 64
        long val = va_arg(args, long);
        KFLog(@"🌐 [CURL] CURLOPT_SSL_VERIFYPEER = %ld", val);
    }
    va_end(args);
    return 0; // 不调用原始函数，避免崩溃
}

static void kf_hookCurl() {
    void *handle = dlopen("/usr/lib/libcurl.4.dylib", RTLD_NOW);
    if (!handle) handle = RTLD_DEFAULT;
    void *sym = dlsym(handle, "curl_easy_setopt");
    if (sym) {
        KFLog(@"🔍 发现 libcurl curl_easy_setopt @ %p", sym);
        // 尝试使用 MSHookFunction（如果 substrate 可用）
        // 如果没有 substrate，这里只是记录地址
    } else {
        KFLog(@"⚠️ 未找到 curl_easy_setopt");
    }
}

#pragma mark - 入口

__attribute__((constructor))
static void kfdiag2_init() {
    NSLog(@"========================================");
    NSLog(@"[KFD] KFun 全面诊断 Tweak v2.0 已加载");
    NSLog(@"========================================");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[KFLogWindow shared] show];
        KFLog(@"✅ 诊断悬浮窗已就绪");
        KFLog(@"📌 操作指南：");
        KFLog(@"   1. 展开悬浮窗看完整日志");
        KFLog(@"   2. 点击'复制'导出日志");
        KFLog(@"   3. 正常操作App，重点观察：");
        KFLog(@"      - activateCode:completion: 回调参数");
        KFLog(@"      - buildSuccessViewWithExpire: 调用时机");
        KFLog(@"      - 哪个VC被push/present到功能主界面");
        KFLog(@"      - setValues: / setHost: 是否被调用");
        KFLog(@"      - TableView reloadData 时 totalRows");

        // 扫描并 hook 所有自定义类
        kf_scanAllClasses();

        // 特别 hook 激活相关方法
        kf_hookActivation();
        kf_hookBuildSuccess();

        // 尝试 hook libcurl
        kf_hookCurl();
    });
}
