#import "CKSafe.h"

CKContainer * _Nullable ALCKContainerCreate(NSString *identifier) {
    if (identifier.length == 0) {
        return nil;
    }
    @try {
        return [CKContainer containerWithIdentifier:identifier];
    } @catch (NSException *exception) {
        NSLog(@"[CloudKitGuard] CKContainer(%@) exception: %@ %@", identifier, exception.name, exception.reason);
        return nil;
    }
}

CKContainer * _Nullable ALCKContainerDefault(void) {
    @try {
        return [CKContainer defaultContainer];
    } @catch (NSException *exception) {
        NSLog(@"[CloudKitGuard] CKContainer.default exception: %@ %@", exception.name, exception.reason);
        return nil;
    }
}
