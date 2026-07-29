// KFunAutopsy.m
// 完全独立设计 · 不参考任何旧绕过逻辑
// 用途：解剖 kfun 验证→初始化→数据加载链路
// 编译：Theos/Logos (GitHub Actions)

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#pragma mark - 日志引擎

@interface KFALogger : NSObject
+ (instancetype)shared;
- (void)log:(NSString *)fmt, ...;
- (NSString *)allText;
- (void)clear;
@property (nonatomic, strong) NSMutableString *buffer;
@property (nonatomic, strong) NSDateFormatter *timeFmt;
@end

@implementation KFALogger
+ (instancetype)shared {
    static KFALogger *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}
- (instancetype)init {
    self = [super init];
    _buffer = [NSMutableString string];
    _timeFmt = [[NSDateFormatter alloc] init];
    _timeFmt.dateFormat = @"HH:mm:ss.SSS";
    return self;
}
- (void)log:(NSString *)fmt, ... {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *ts = [_timeFmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
    [_buffer appendString:line];
    NSString *path = @"/var/mobile/Documents/kfun_autopsy.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    else { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"KFALogAppend" object:line];
}
- (NSString *)allText { return [_buffer copy]; }
- (void)clear { [_buffer setString:@""]; [[@"" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:@"/var/mobile/Documents/kfun_autopsy.log" atomically:YES]; }
@end

#define KFA(fmt, ...) [[KFALogger shared] log:fmt, ##__VA_ARGS__]

#pragma mark - 悬浮解剖窗

@interface KFAWindow : UIWindow
@property (nonatomic, strong) UITextView *console;
@property (nonatomic, strong) UIView *topBar;
@end

@implementation KFAWindow

- (instancetype)init {
    CGRect sr = [UIScreen mainScreen].bounds;
    CGFloat W = sr.size.width * 0.88;
    CGFloat H = sr.size.height * 0.50;
    self = [super initWithFrame:CGRectMake((sr.size.width-W)/2, 60, W, H)];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 200;
        self.backgroundColor = [UIColor colorWithWhite:0.03 alpha:0.94];
        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0].CGColor;
        self.hidden = NO;
        
        _topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 34)];
        _topBar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
        [self addSubview:_topBar];
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, W-140, 26)];
        title.text = @"🔬 KFun Autopsy";
        title.font = [UIFont boldSystemFontOfSize:12];
        title.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.5 alpha:1.0];
        [_topBar addSubview:title];
        
        UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
        cp.frame = CGRectMake(W-130, 2, 60, 30);
        [cp setTitle:@"📋复制" forState:UIControlStateNormal];
        cp.titleLabel.font = [UIFont systemFontOfSize:11];
        [cp setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
        [cp addTarget:self action:@selector(copyAll) forControlEvents:UIControlEventTouchUpInside];
        [_topBar addSubview:cp];
        
        UIButton *cl = [UIButton buttonWithType:UIButtonTypeSystem];
        cl.frame = CGRectMake(W-65, 2, 60, 30);
        [cl setTitle:@"🗑清空" forState:UIControlStateNormal];
        cl.titleLabel.font = [UIFont systemFontOfSize:11];
        [cl setTitleColor:[UIColor orangeColor] forState:UIControlStateNormal];
        [cl addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
        [_topBar addSubview:cl];
        
        _console = [[UITextView alloc] initWithFrame:CGRectMake(3, 38, W-6, H-42)];
        _console.backgroundColor = [UIColor clearColor];
        _console.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.4 alpha:1.0];
        _console.font = [UIFont fontWithName:@"Courier" size:9];
        _console.editable = NO;
        _console.selectable = YES;
        _console.showsVerticalScrollIndicator = YES;
        [self addSubview:_console];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [_topBar addGestureRecognizer:pan];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNewLine:) name:@"KFALogAppend" object:nil];
    }
    return self;
}

- (void)onNewLine:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = n.object;
        self.console.text = [NSString stringWithFormat:@"%@%@", self.console.text, line];
        [self.console scrollRangeToVisible:NSMakeRange(self.console.text.length-1, 1)];
    });
}

- (void)copyAll {
    UIPasteboard.generalPasteboard.string = [KFALogger shared].allText;
    KFA(@"[SYS] 全部日志已复制到剪贴板");
}

- (void)clearAll {
    [[KFALogger shared] clear];
    self.console.text = @"";
    KFA(@"=== 日志已清空 ===");
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

@end

static KFAWindow *g_win = nil;

#pragma mark - 辅助

static void dumpDict(id obj, int depth) {
    if (!obj || ![obj isKindOfClass:[NSDictionary class]]) {
        KFA(@"%@⚠️ 非字典: %@ (%@)", [@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0], obj, NSStringFromClass([obj class]));
        return;
    }
    NSDictionary *d = obj;
    for (id k in d) {
        id v = d[k];
        NSString *ind = [@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0];
        if ([v isKindOfClass:[NSDictionary class]]) {
            KFA(@"%@\"%@\" → {", ind, k);
            dumpDict(v, depth+1);
            KFA(@"%@}", ind);
        } else if ([v isKindOfClass:[NSArray class]]) {
            KFA(@"%@\"%@\" → [%lu]", ind, k, (unsigned long)[(NSArray*)v count]);
            for (id item in (NSArray*)v) KFA(@"%@  · %@", ind, item);
        } else {
            NSString *desc = [v description];
            if (desc.length > 120) desc = [desc substringToIndex:120];
            KFA(@"%@\"%@\" = \"%@\" [%@]", ind, k, desc, NSStringFromClass([v class]));
        }
    }
}

static void logStack(int skip, int max) {
    NSArray *syms = [NSThread callStackSymbols];
    for (int i = skip+2; i < MIN((int)syms.count, skip+2+max); i++) KFA(@"  ↳ %@", syms[i]);
}

#pragma mark - Hook 1: 激活控制器

%hook WWWActivationViewController

- (void)viewDidLoad {
    KFA(@"[ACT] viewDidLoad");
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    KFA(@"[ACT] viewDidAppear");
    %orig;
}

// ⭐ 观察点击验证
- (void)onTapVerify {
    KFA(@"[ACT] ⭐ onTapVerify 触发");
    logStack(0, 4);
    %orig;
}

// ⭐ 观察网络验证
- (void)activateCode:(NSString *)code completion:(void (^)(BOOL success, id data))completion {
    KFA(@"[ACT] ⭐ activateCode: \"%@\"", code);
    logStack(0, 3);
    void (^wrapped)(BOOL, id) = ^(BOOL success, id data) {
        KFA(@"[ACT] ⭐ activateCode completion 回调");
        KFA(@"[ACT]   success = %d", success);
        KFA(@"[ACT]   data class = %@", NSStringFromClass([data class]));
        if ([data isKindOfClass:[NSDictionary class]]) { KFA(@"[ACT]   data 结构:"); dumpDict(data, 1); }
        else if (data) KFA(@"[ACT]   data = %@", [data description]);
        if (completion) completion(success, data);
    };
    %orig(code, wrapped);
}

// ⭐ 观察成功弹窗及其 completion block（这是旧代码断裂的关键点）
- (void)showSuccess:(id)msg completion:(void (^)(void))completion {
    KFA(@"[ACT] ⭐ showSuccess: %@", msg);
    KFA(@"[ACT]   completion block = %@", completion);
    void (^wrapped)(void) = ^{
        KFA(@"[ACT] ⭐ showSuccess completion block 开始执行");
        logStack(0, 6);
        if (completion) completion();
        KFA(@"[ACT]   showSuccess completion block 执行完毕");
    };
    %orig(msg, wrapped);
}

- (void)showError:(id)msg {
    KFA(@"[ACT] showError: %@", msg);
    logStack(0, 4);
    %orig;
}

- (void)buildSuccessViewWithExpire:(id)expire {
    KFA(@"[ACT] buildSuccessViewWithExpire: %@", expire);
    logStack(0, 4);
    %orig;
}

- (BOOL)isActivated {
    BOOL v = %orig;
    KFA(@"[ACT] isActivated → %d", v);
    return v;
}

- (BOOL)isVerified {
    BOOL v = %orig;
    KFA(@"[ACT] isVerified → %d", v);
    return v;
}

%end

#pragma mark - Hook 2: 主页控制器

%hook ViewController

- (void)viewDidLoad {
    KFA(@"[MAIN] viewDidLoad");
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    KFA(@"[MAIN] viewDidAppear");
    %orig;
}

- (void)setupAfterActivation {
    KFA(@"[MAIN] ⭐ setupAfterActivation 调用");
    logStack(0, 5);
    %orig;
}

- (void)setupBackgroundKeepAlive {
    KFA(@"[MAIN] setupBackgroundKeepAlive 调用");
    %orig;
}

// ⭐ 关键：观察 tableView 数据源（直接回答"为什么没内容"）
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    NSInteger n = %orig;
    KFA(@"[MAIN] tableView rows=%ld (section=%ld)", (long)n, (long)section);
    return n;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = %orig;
    KFA(@"[MAIN] tableView cell[%ld,%ld] = %@", (long)ip.section, (long)ip.row, c.textLabel.text);
    return c;
}

- (id)tableView {
    id v = %orig;
    KFA(@"[MAIN] getter tableView → %@", v ? @"非nil" : @"nil");
    return v;
}

- (id)langSeg {
    id v = %orig;
    KFA(@"[MAIN] getter langSeg → %@", v ? @"非nil" : @"nil");
    return v;
}

%end

#pragma mark - Hook 3: 网络层

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    KFA(@"[NET] %@ %@", req.HTTPMethod, req.URL.absoluteString);
    if (req.HTTPBody) {
        NSString *b = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
        if (b) KFA(@"[NET] BODY: %@", b);
    }
    if (req.allHTTPHeaderFields) KFA(@"[NET] HDR: %@", req.allHTTPHeaderFields);
    
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSHTTPURLResponse *h = (NSHTTPURLResponse *)r;
        if (h) KFA(@"[NET] RESP %ld ← %@", (long)h.statusCode, h.URL.absoluteString);
        if (e) KFA(@"[NET] ERR: %@", e);
        if (d) {
            NSString *t = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (t && t.length < 800) {
                KFA(@"[NET] DATA: %@", t);
                id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
                if ([j isKindOfClass:[NSDictionary class]]) { KFA(@"[NET] JSON:"); dumpDict(j, 1); }
            } else if (t) KFA(@"[NET] DATA: (text, %lu chars)", (unsigned long)t.length);
            else KFA(@"[NET] DATA: (binary, %lu bytes)", (unsigned long)d.length);
        }
        if (cb) cb(d, r, e);
    };
    return %orig(req, wrapped);
}

%end

#pragma mark - Hook 4: 存储层

%hook NSUserDefaults

- (void)setObject:(id)obj forKey:(NSString *)key {
    KFA(@"[STORE] SET \"%@\" = \"%@\"", key, obj);
    %orig;
}

- (id)objectForKey:(NSString *)key {
    id v = %orig;
    NSArray *keys = @[@"auth", @"token", @"license", @"expire", @"kfun", @"xpf", @"config", @"verify", @"status", @"user", @"device"];
    for (NSString *k in keys) if ([key containsString:k]) { KFA(@"[STORE] GET \"%@\" = \"%@\"", key, v); break; }
    return v;
}

%end

#pragma mark - Hook 5: dylib 加载

%hookf(void *, dlopen, const char *path, int mode) {
    void *h = %orig;
    if (path) {
        NSString *p = [NSString stringWithUTF8String:path];
        if ([p containsString:@"xpf"] || [p containsString:@"kfun"]) {
            KFA(@"[DYLIB] dlopen: %s → %p", path, h);
            logStack(0, 5);
        }
    }
    return h;
}

%hookf(void *, dlsym, void *h, const char *sym) {
    void *a = %orig;
    if (sym) {
        NSString *s = [NSString stringWithUTF8String:sym];
        if ([s containsString:@"xpf"] || [s containsString:@"init"] || [s containsString:@"start"] || [s containsString:@"setup"]) {
            KFA(@"[DYLIB] dlsym: %s → %p", sym, a);
        }
    }
    return a;
}

%end

#pragma mark - Hook 6: 弹窗

%hook UIAlertController

+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style {
    KFA(@"[ALERT] TITLE: \"%@\"", title);
    KFA(@"[ALERT] MSG: \"%@\"", message);
    logStack(0, 5);
    return %orig(title, message, style);
}

%end

#pragma mark - Hook 7: 持续认证检查

%hook NSObject

- (void)startContinuousAuthCheck {
    KFA(@"[AUTH] ⭐ startContinuousAuthCheck 调用");
    logStack(0, 6);
    %orig;
}

%end

#pragma mark - 构造函数

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_win = [[KFAWindow alloc] init];
        KFA(@"=== KFun Autopsy 启动 ===");
        KFA(@"使用说明：");
        KFA(@"1. 输入任意假卡密，点击验证");
        KFA(@"2. 观察 [ACT] 激活流程 和 [NET] 网络请求");
        KFA(@"3. 如果用了破解版 dylib，对比 [DYLIB] 加载差异");
        KFA(@"4. 点击 📋复制，把日志发给我");
        KFA(@"5. 重点观察 ⭐ 标记的关键节点");
        
        unsigned int c = _dyld_image_count();
        for (unsigned int i = 0; i < c; i++) {
            const char *n = _dyld_get_image_name(i);
            if (strstr(n, "xpf") || strstr(n, "kfun") || strstr(n, "inject") || strstr(n, "substrate") || strstr(n, "Autopsy")) {
                KFA(@"[IMG] %s", n);
            }
        }
    });
}
