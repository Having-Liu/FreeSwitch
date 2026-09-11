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

+ (id)blueLightClient {
    FSEnsureCoreBrightnessLoaded();
    Class cls = NSClassFromString(@"CBBlueLightClient");
    if (!cls) { return nil; }
    return [[cls alloc] init];
}

+ (id)trueToneClient {
    FSEnsureCoreBrightnessLoaded();
    Class cls = NSClassFromString(@"CBTrueToneClient");
    if (!cls) { return nil; }
    return [[cls alloc] init];
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
    SEL setEnabled = NSSelectorFromString(@"setEnabled:");
    if ([client respondsToSelector:setEnabled]) {
        ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(client, setEnabled, enabled);
    }
    if (enabled) {
        SEL setStrength = NSSelectorFromString(@"setStrength:commit:");
        if ([client respondsToSelector:setStrength]) {
            ((BOOL (*)(id, SEL, float, BOOL))objc_msgSend)(client, setStrength, 0.9f, YES);
        }
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
