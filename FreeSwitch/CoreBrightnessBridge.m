#import "CoreBrightnessBridge.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <string.h>

static void FSEnsureCoreBrightnessLoaded(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
    });
}

@implementation CoreBrightnessBridge

// 客户端缓存住，不要每次调用都新建。
// 每建一个就是一次 XPC 连接的建立与拆除，而状态核对每 5 秒会读一次夜览和原彩——
// 一个整天常驻的菜单栏 App 这样空耗电量，日志里能看到每 5 秒一条连接取消。
+ (id)blueLightClient {
    static id client = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        FSEnsureCoreBrightnessLoaded();
        Class cls = NSClassFromString(@"CBBlueLightClient");
        if (cls) { client = [[cls alloc] init]; }
    });
    return client;
}

+ (id)trueToneClient {
    static id client = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        FSEnsureCoreBrightnessLoaded();
        Class cls = NSClassFromString(@"CBTrueToneClient");
        if (cls) { client = [[cls alloc] init]; }
    });
    return client;
}

#pragma mark - Night Shift

+ (BOOL)nightShiftSupported {
    FSEnsureCoreBrightnessLoaded();
    return NSClassFromString(@"CBBlueLightClient") != nil;
}

+ (BOOL)nightShiftEnabled {
    id client = [self blueLightClient];
    if (!client) { return NO; }
    SEL sel = NSSelectorFromString(@"getBlueLightStatus:");
    if (![client respondsToSelector:sel]) { return NO; }
    // BlueLightStatus 结构体：前若干个 int 字段，enabled 位于偏移 4。
    unsigned char status[128] = {0};
    BOOL (*getStatus)(id, SEL, void *) = (BOOL (*)(id, SEL, void *))objc_msgSend;
    BOOL ok = getStatus(client, sel, status);
    if (!ok) { return NO; }
    int enabled = 0;
    memcpy(&enabled, status + 4, sizeof(int));
    return enabled != 0;
}

+ (void)setNightShiftEnabled:(BOOL)enabled {
    id client = [self blueLightClient];
    if (!client) { return; }
    // 只切换开关，保留用户在系统设置里配置的强度/时间表，不做覆盖。
    SEL setEnabled = NSSelectorFromString(@"setEnabled:");
    if ([client respondsToSelector:setEnabled]) {
        ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(client, setEnabled, enabled);
    }
}

#pragma mark - True Tone

+ (BOOL)trueToneSupported {
    id client = [self trueToneClient];
    if (!client) { return NO; }
    SEL sel = NSSelectorFromString(@"available");
    if (![client respondsToSelector:sel]) { return NO; }
    return ((BOOL (*)(id, SEL))objc_msgSend)(client, sel);
}

+ (BOOL)trueToneEnabled {
    id client = [self trueToneClient];
    if (!client) { return NO; }
    SEL sel = NSSelectorFromString(@"enabled");
    if (![client respondsToSelector:sel]) { return NO; }
    return ((BOOL (*)(id, SEL))objc_msgSend)(client, sel);
}

+ (void)setTrueToneEnabled:(BOOL)enabled {
    id client = [self trueToneClient];
    if (!client) { return; }
    SEL sel = NSSelectorFromString(@"setEnabled:");
    if ([client respondsToSelector:sel]) {
        ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(client, sel, enabled);
    }
}

@end
