#import <CloudKit/CloudKit.h>

NS_ASSUME_NONNULL_BEGIN

/// CKContainer 初始化在 iOS 26/27 上遇到畸形 iCloud entitlement 会抛 CKException。
/// Swift 接不住 NSException，必须走 ObjC @try/@catch。
CKContainer * _Nullable ALCKContainerCreate(NSString *identifier);
CKContainer * _Nullable ALCKContainerDefault(void);

NS_ASSUME_NONNULL_END
