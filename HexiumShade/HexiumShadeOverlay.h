#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^HexiumShadeApplyCompletion)(BOOL success, NSError * _Nullable error);
typedef void (^HexiumShadeApplyHandler)(NSDictionary<NSString *, NSNumber *> *options,
                                        HexiumShadeApplyCompletion completion);

@interface HexiumShadeOverlay : NSObject

+ (void)showOverlay;

/** Register a callback from the host app's own renderer. */
+ (void)setApplyHandler:(nullable HexiumShadeApplyHandler)handler;

@end

NS_ASSUME_NONNULL_END
