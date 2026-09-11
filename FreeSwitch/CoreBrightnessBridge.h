#import <Foundation/Foundation.h>

/// 通过运行时动态调用私有框架 CoreBrightness，实现“夜览 / 原彩显示”控制。
/// 不在链接期引用私有类符号（用 dlopen + NSClassFromString + objc_msgSend），
/// 因此不需要链接私有框架，签名后也能在非商店 App 里正常工作。
@interface CoreBrightnessBridge : NSObject

+ (BOOL)nightShiftSupported;
+ (BOOL)nightShiftEnabled;
+ (void)setNightShiftEnabled:(BOOL)enabled;

+ (BOOL)trueToneSupported;
+ (BOOL)trueToneEnabled;
+ (void)setTrueToneEnabled:(BOOL)enabled;

@end
