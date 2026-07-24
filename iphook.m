//
//  iphook.m - KFun 卡密验证 Bypass
//  目标: WWWActivationViewController
//  策略: 只 Hook activateCode:completion:，直接回调成功
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[IPH] " fmt, ##__VA_ARGS__)

// ============================================================
// 隐藏遮罩
// ============================================================
static void hideMask(id self) {
    id mask = nil;
    @try { mask = [self valueForKey:@"authMaskView"]; } @catch (NSException *e) {}
    if (!mask) @try { mask = [self valueForKey:@"_authMaskView"]; } @catch (NSException *e) {}

    if (mask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [mask setValue:@YES forKey:@"hidden"];
            [(UIView *)mask setUserInteractionEnabled:NO];
            [(UIView *)mask removeFromSuperview];
            LOG(@"遮罩已移除");
        });
    }
}

// ============================================================
// 尝试进入主界面
// ============================================================
static void tryEnterMain(id self) {
    // 先尝试 self 上的方法
    if ([self respondsToSelector:@selector(setupAfterActivation)]) {
        LOG(@"调用 setupAfterActivation");
        dispatch_async(dispatch_get_main_queue(), ^{
            ((void(*)(id, SEL))objc_msgSend)(self, @selector(setupAfterActivation));
        });
        return;
    }

    // 尝试从当前 VC 找
    dispatch_async(dispatch_get_main_queue(), ^{
        id vc = nil;
        @try {
            UIWindowScene *scene = nil;
            for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) { scene = s; break; }
            }
            UIWindow *window = scene ? scene.keyWindow : [UIApplication sharedApplication].keyWindow;
            vc = window.rootViewController;
            while (vc && [vc respondsToSelector:@selector(presentedViewController)] && [vc presentedViewController])
                vc = [vc presentedViewController];
        } @catch (NSException *e) { return; }

        if (!vc) return;

        if ([vc respondsToSelector:@selector(setupAfterActivation)]) {
            LOG(@"从 VC 调用 setupAfterActivation");
            ((void(*)(id, SEL))objc_msgSend)(vc, @selector(setupAfterActivation));
            return;
        }

        for (id child in [vc valueForKey:@"childViewControllers"]) {
            if ([child respondsToSelector:@selector(setupAfterActivation)]) {
                LOG(@"从子控制器调用 setupAfterActivation");
                ((void(*)(id, SEL))objc_msgSend)(child, @selector(setupAfterActivation));
                return;
            }
        }
    });
}

// ============================================================
// Hook 实现
// ============================================================

static void hook_activateCode(id self, SEL _cmd, NSString *code, id completion) {
    LOG(@"Bypass activateCode: %@", code);

    // 伪造成功数据
    NSDictionary *fakeData = @{
        @"code": @0,
        @"msg": @"success",
        @"data": @{
            @"expire": @"2099-12-31 23:59:59",
            @"type": @"lifetime"
        }
    };

    // 回调 - 用 id 类型避免 block 签名不匹配
    if (completion) {
        @try {
            // 尝试各种 block 签名
            void (^block1)(BOOL, id) = completion;
            block1(YES, fakeData);
        } @catch (NSException *e1) {
            @try {
                void (^block2)(BOOL, NSDictionary *) = completion;
                block2(YES, fakeData);
            } @catch (NSException *e2) {
                @try {
                    void (^block3)(id, id) = completion;
                    block3(fakeData, nil);
                } @catch (NSException *e3) {
                    LOG(@"Block 回调失败: %@", e3);
                }
            }
        }
    }

    // 移除遮罩
    hideMask(self);

    // 尝试进入主界面
    tryEnterMain(self);
}

// ============================================================
// 初始化
// ============================================================
static void doInit() {
    LOG(@"开始 Hook...");

    Class cls = objc_getClass("WWWActivationViewController");
    if (!cls) {
        LOG(@"找不到 WWWActivationViewController!");
        return;
    }
    LOG(@"找到类: WWWActivationViewController");

    Method m = class_getInstanceMethod(cls, @selector(activateCode:completion:));
    if (m) {
        method_setImplementation(m, (IMP)hook_activateCode);
        LOG(@"Hooked activateCode:completion:");
    } else {
        LOG(@"找不到 activateCode:completion:");
    }

    LOG(@"初始化完成");
}

__attribute__((constructor))
static void iphook_init() {
    LOG(@"========================================");
    LOG(@"KFun Bypass 已加载");
    LOG(@"========================================");

    // 延迟初始化，确保 UIKit 准备好
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        doInit();
    });
}
