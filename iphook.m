//
//  kfunTweak.m
//  一键复制保存为 kfunTweak.m
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <WebKit/WebKit>

#pragma mark - 日志系统

static UITextView *gLogView = nil;

static void KFLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                  dateStyle:NSDateFormatterNoStyle
                                                  timeStyle:NSDateFormatterMediumStyle];
    NSString *line = [NSString stringWithFormat:@"[%@] %@", ts, msg];
    NSLog(@"[KFunTweak] %@", line);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gLogView) {
            NSString *txt = gLogView.text ?: @"";
            NSString *up = [NSString stringWithFormat:@"%@\n%@", line, txt];
            if (up.length > 8000) up = [up substringToIndex:8000];
            gLogView.text = up;
            NSRange b = NSMakeRange(gLogView.text.length - 1, 1);
            [gLogView scrollRangeToVisible:b];
        }
    });
}

#pragma mark - 辅助：获取所有 Window（兼容 iOS 15+）

static NSArray<UIWindow *> *KFAllWindows(void) {
    NSMutableArray<UIWindow *> *arr = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                [arr addObjectsFromArray:ws.windows];
            }
        }
    }
    if (arr.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [arr addObjectsFromArray:[UIApplication sharedApplication].windows];
#pragma clang diagnostic pop
    }
    return arr;
}

#pragma mark - 悬浮窗面板

@interface KFDebugPanel : UIView
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, assign) BOOL isExpanded;
@end

@implementation KFDebugPanel

+ (instancetype)shared {
    static KFDebugPanel *p = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat sw = [UIScreen mainScreen].bounds.size.width;
        p = [[self alloc] initWithFrame:CGRectMake(sw - 75, 140, 60, 60)];
    });
    return p;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.isExpanded = NO;
        self.backgroundColor = [UIColor clearColor];
        
        self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatBtn.frame = CGRectMake(0, 0, 60, 60);
        self.floatBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.75 blue:1.0 alpha:0.95];
        self.floatBtn.layer.cornerRadius = 30;
        self.floatBtn.layer.shadowColor = [UIColor blackColor].CGColor;
        self.floatBtn.layer.shadowOffset = CGSizeMake(0, 3);
        self.floatBtn.layer.shadowRadius = 8;
        self.floatBtn.layer.shadowOpacity = 0.35;
        [self.floatBtn setTitle:@"🔥" forState:UIControlStateNormal];
        self.floatBtn.titleLabel.font = [UIFont systemFontOfSize:26];
        [self.floatBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.floatBtn];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self.floatBtn addGestureRecognizer:pan];
        
        self.contentView = [[UIView alloc] initWithFrame:CGRectMake(-245, 70, 310, 420)];
        self.contentView.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.96];
        self.contentView.layer.cornerRadius = 16;
        self.contentView.layer.borderWidth = 1.5;
        self.contentView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.75 blue:1.0 alpha:1.0].CGColor;
        self.contentView.hidden = YES;
        self.contentView.alpha = 0;
        [self addSubview:self.contentView];
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 220, 24)];
        title.text = @"KFun Radar Debug";
        title.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:1.0 alpha:1.0];
        title.font = [UIFont boldSystemFontOfSize:15];
        [self.contentView addSubview:title];
        
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(270, 8, 32, 32);
        [close setTitle:@"✕" forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont systemFontOfSize:20];
        [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        [close addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:close];
        
        NSArray *btns = @[
            @{@"title":@"🗑 移除遮罩", @"sel":@"btnRemoveMask:"},
            @{@"title":@"🌐 查看WebView", @"sel":@"btnInspect:"},
            @{@"title":@"📝 清空日志", @"sel":@"btnClear:"}
        ];
        for (int i = 0; i < btns.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(10 + i * 100, 40, 95, 30);
            b.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
            b.layer.cornerRadius = 6;
            [b setTitle:btns[i][@"title"] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:11];
            [b setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
            [b addTarget:self action:NSSelectorFromString(btns[i][@"sel"]) forControlEvents:UIControlEventTouchUpInside];
            [self.contentView addSubview:b];
        }
        
        gLogView = [[UITextView alloc] initWithFrame:CGRectMake(8, 78, 294, 334)];
        gLogView.backgroundColor = [UIColor clearColor];
        gLogView.textColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.3 alpha:1.0];
        gLogView.font = [UIFont fontWithName:@"Menlo" size:10];
        gLogView.editable = NO;
        gLogView.selectable = YES;
        [self.contentView addSubview:gLogView];
    }
    return self;
}

- (void)toggle { self.isExpanded ? [self hide] : [self show]; }
- (void)show {
    self.isExpanded = YES;
    self.contentView.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{ self.contentView.alpha = 1.0; }];
}
- (void)hide {
    self.isExpanded = NO;
    [UIView animateWithDuration:0.2 animations:^{ self.contentView.alpha = 0.0; }
                    completion:^(BOOL f){ self.contentView.hidden = YES; }];
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.superview];
    CGRect f = self.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    self.frame = f;
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)btnRemoveMask:(id)sender { extern void RemoveAllAuthMasks(void); RemoveAllAuthMasks(); }
- (void)btnInspect:(id)sender   { extern void InspectWebViews(void); InspectWebViews(); }
- (void)btnClear:(id)sender      { gLogView.text = @""; }

@end

#pragma mark - 遮罩移除引擎

static void ScanMaskInView(UIView *view, int depth) {
    if (depth > 25) return;
    
    CGRect vf = view.frame;
    if (vf.size.width > 320 && vf.size.height > 500) {
        BOOL hasText = NO;
        for (UIView *sv in view.subviews) {
            if ([sv isKindOfClass:[UITextField class]] || [sv isKindOfClass:[UIButton class]]) {
                NSString *t = [(UIButton *)sv currentTitle] ?: @"";
                if ([t containsString:@"验证"] || [t containsString:@"激活"] || [t containsString:@"登录"] || [t containsString:@"确认"]) {
                    hasText = YES; break;
                }
            }
        }
        if (hasText && view.alpha <= 0.95) {
            [view removeFromSuperview];
            KFLog(@"🗑 移除验证遮罩 (策略1)");
            return;
        }
    }
    
    if ([view respondsToSelector:@selector(authMaskView)]) {
        UIView *mask = nil;
        @try { mask = [view performSelector:@selector(authMaskView)]; } @catch (id e) {}
        if (mask && mask.superview) {
            [mask removeFromSuperview];
            KFLog(@"🗑 KVC 移除 authMaskView");
        }
    }
    
    NSArray *subs = [view.subviews copy];
    for (UIView *sv in subs) ScanMaskInView(sv, depth + 1);
}

void RemoveAllAuthMasks(void) {
    for (UIWindow *win in KFAllWindows()) {
        ScanMaskInView(win, 0);
    }
}

#pragma mark - WebView 检查

static void _inspect(UIView *v, int d) {
    if (d > 20) return;
    NSString *cls = NSStringFromClass([v class]);
    if ([cls isEqualToString:@"WKWebView"] || [cls isEqualToString:@"UIWebView"]) {
        NSURL *url = nil;
        if ([v respondsToSelector:@selector(URL)]) {
            url = [v performSelector:@selector(URL)];
        }
        KFLog(@"🌐 发现 %@ URL=%@", cls, url);
    }
    for (UIView *sv in v.subviews) _inspect(sv, d + 1);
}

void InspectWebViews(void) {
    for (UIWindow *win in KFAllWindows()) {
        _inspect(win, 0);
    }
}

#pragma mark - Method Swizzling

static void (*orig_vcAppear)(id, SEL, BOOL);
static void hook_vcAppear(id self, SEL _cmd, BOOL animated) {
    orig_vcAppear(self, _cmd, animated);
    KFLog(@"📱 VC: %@", NSStringFromClass([self class]));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RemoveAllAuthMasks();
    });
}

static id (*orig_wkLoadReq)(id, SEL, id);
static id hook_wkLoadReq(id self, SEL _cmd, id req) {
    KFLog(@"🌐 loadRequest: %@", [(NSURLRequest *)req URL].absoluteString);
    return orig_wkLoadReq(self, _cmd, req);
}

static id (*orig_wkLoadFile)(id, SEL, id, id);
static id hook_wkLoadFile(id self, SEL _cmd, id url, id base) {
    KFLog(@"📄 loadFileURL: %@", url);
    return orig_wkLoadFile(self, _cmd, url, base);
}

static id (*orig_wkLoadHTML)(id, SEL, id, id);
static id hook_wkLoadHTML(id self, SEL _cmd, id str, id base) {
    KFLog(@"📝 loadHTMLString len=%lu", (unsigned long)[(NSString *)str length]);
    return orig_wkLoadHTML(self, _cmd, str, base);
}

#pragma mark - Constructor

__attribute__((constructor))
static void kfun_tweak_init() {
    KFLog(@"🚀 KFun Tweak 已注入");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    kw = [(UIWindowScene *)scene windows].firstObject;
                    break;
                }
            }
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (!kw) kw = [UIApplication sharedApplication].keyWindow;
        if (!kw) kw = [[UIApplication sharedApplication].windows firstObject];
#pragma clang diagnostic pop
        
        if (kw) {
            KFDebugPanel *p = [KFDebugPanel shared];
            [kw addSubview:p];
            KFLog(@"✅ 悬浮窗已挂载");
        }
        RemoveAllAuthMasks();
    });
    
    [NSTimer scheduledTimerWithTimeInterval:2.5 repeats:YES block:^(NSTimer *t) {
        RemoveAllAuthMasks();
    }];
    
    Method m1 = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
    if (m1) {
        orig_vcAppear = (void (*)(id, SEL, BOOL))method_getImplementation(m1);
        method_setImplementation(m1, (IMP)hook_vcAppear);
    }
    
    Class wk = NSClassFromString(@"WKWebView");
    if (wk) {
        Method m2 = class_getInstanceMethod(wk, @selector(loadRequest:));
        if (m2) { orig_wkLoadReq = (id (*)(id, SEL, id))method_getImplementation(m2); method_setImplementation(m2, (IMP)hook_wkLoadReq); }
        Method m3 = class_getInstanceMethod(wk, @selector(loadFileURL:allowingReadAccessToURL:));
        if (m3) { orig_wkLoadFile = (id (*)(id, SEL, id, id))method_getImplementation(m3); method_setImplementation(m3, (IMP)hook_wkLoadFile); }
        Method m4 = class_getInstanceMethod(wk, @selector(loadHTMLString:baseURL:));
        if (m4) { orig_wkLoadHTML = (id (*)(id, SEL, id, id))method_getImplementation(m4); method_setImplementation(m4, (IMP)hook_wkLoadHTML); }
    }
}
