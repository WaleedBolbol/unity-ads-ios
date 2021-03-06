#import "UnityAds.h"
#import "USTRAppSheet.h"
#import "UADSApiAdUnit.h"
#import "USRVWebViewApp.h"
#import "USTRAppSheetError.h"
#import "USTRAppSheetEvent.h"
#import "USRVWebViewEventCategory.h"

@interface USTRAppSheet ()

@property NSMutableDictionary<NSString*, SKStoreProductViewController*>* appSheetCache;
@property NSMutableSet<NSString*>* appSheetLoading;
@property NSDictionary* presentingParameters;
@property (nonatomic, assign) BOOL presentingAnimated;

@end

@implementation USTRAppSheet

- (id)init {
    self = [super init];
    if(self) {
        self.appSheetCache = [[NSMutableDictionary alloc] init];
        self.appSheetLoading = [[NSMutableSet alloc] init];
        
        Class storeProductViewControllerClass = NSClassFromString(@"SKStoreProductViewController");
        self.canOpenAppSheet = [storeProductViewControllerClass instancesRespondToSelector:@selector(loadProductWithParameters:completionBlock:)];
    }
    return self;
}

- (void)prepareAppSheet:(NSDictionary *)parameters prepareTimeoutInSeconds:(int)timeout completionBlock:(nullable void(^)(BOOL result, NSString * __nullable error))block {
    NSString *iTunesId = [self getItunesIdFromParameters:parameters];
    self.prepareTimeoutInSeconds = timeout;
    if ([self getCachedController:iTunesId]) {
        block(true, nil);
    } else if(![self.appSheetLoading containsObject:iTunesId]) {
        [self.appSheetLoading addObject:iTunesId];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            SKStoreProductViewController *viewController = [[SKStoreProductViewController alloc] init];
            [viewController setDelegate:self];
            [viewController setModalPresentationCapturesStatusBarAppearance:true];
            
            __block BOOL finished = NO;
            __block BOOL cancelled = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.prepareTimeoutInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!finished) {
                    cancelled = YES;
                    USRVLogDebug(@"Timeout. Preloading product information failed for id: %@", iTunesId);
                    block(false, USRVNSStringFromAppSheetError(kUnityServicesAppSheetErrorTimeout));
                }
            });
            
            [viewController loadProductWithParameters:parameters completionBlock:^(BOOL result, NSError *error) {
                finished = YES;
                if (cancelled) {
                    return;
                }
                
                if (result) {
                    USRVLogDebug(@"Preloading product information succeeded for id: %@.", iTunesId);
                    [self.appSheetCache setValue:viewController forKey:iTunesId];
                    block(true, nil);
                } else {
                    USRVLogDebug(@"Preloading product information failed for id: %@ with error: %@", iTunesId, error);
                    block(false, [error description]);
                }
            }];
        });
    } else {
        block(false, USRVNSStringFromAppSheetError(kUnityServicesAppSheetErrorAlreadyPreparing));
    }
}

- (void)presentAppSheet:(NSDictionary *)parameters animated:(BOOL)animated completionBlock:(nullable void (^)(BOOL result, NSString * __nullable error))block {
    NSString *iTunesId = [self getItunesIdFromParameters:parameters];
    SKStoreProductViewController* cachedController = [self getCachedController:iTunesId];
    if(cachedController) {
        if(self.presentingParameters != nil) {
            block(false, USRVNSStringFromAppSheetError(kUnityServicesAppSheetErrorAlreadyPresenting));
            return;
        }
        self.presentingParameters = parameters;
        self.presentingAnimated = animated;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UADSApiAdUnit getAdUnit] presentViewController:cachedController animated:animated completion:^{
                if ([USRVWebViewApp getCurrentApp]) {
                    [[USRVWebViewApp getCurrentApp] sendEvent:USRVNSStringFromAppSheetEvent(kAppSheetOpened) category:USRVNSStringFromWebViewEventCategory(kUnityServicesWebViewEventCategoryAppSheet) param1:parameters, nil];
                }
            }];
        });
        
        block(true, nil);
    } else {
        block(false, USRVNSStringFromAppSheetError(kUnityServicesAppSheetErrorNotFound));
    }
}

- (void)destroyAppSheet {
    self.presentingParameters = nil;
    [self.appSheetCache removeAllObjects];
    [self.appSheetLoading removeAllObjects];
}

- (BOOL)destroyAppSheet:(NSDictionary *)parameters {
    NSString *iTunesId = [self getItunesIdFromParameters:parameters];
    if([self getCachedController:iTunesId]) {
        [self.appSheetCache removeObjectForKey:iTunesId];
        [self.appSheetLoading removeObject:iTunesId];
        return true;
    }
    
    return false;
}

- (NSString *)getItunesIdFromParameters:(NSDictionary *)parameters {
    return [parameters objectForKey:@"id"];
}

- (SKStoreProductViewController *)getCachedController:(NSString *)iTunesId {
    return [self.appSheetCache objectForKey:iTunesId];
}

- (void)productViewControllerDidFinish:(SKStoreProductViewController *)viewController {
    if (viewController.presentingViewController != nil) {
        [viewController.presentingViewController dismissViewControllerAnimated:self.presentingAnimated completion:^{
            if ([USRVWebViewApp getCurrentApp]) {
                [[USRVWebViewApp getCurrentApp] sendEvent:USRVNSStringFromAppSheetEvent(kAppSheetClosed) category:USRVNSStringFromWebViewEventCategory(kUnityServicesWebViewEventCategoryAppSheet) param1:self.presentingParameters, nil];
            }
            self.presentingParameters = nil;
        }];
    }
}

@end
