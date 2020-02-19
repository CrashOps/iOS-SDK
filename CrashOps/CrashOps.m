//
//  CrashOps.m
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "CrashOps.h"
#import "CrashOpsController.h"
#import <KZCrash/KSCrash.h>

// Everything that is decalred here (the implementation file) is considered as PRIVATE FIELDS & METHODS (as long as they're not exported in the header file).
// Read more at: https://medium.com/@victorleungtw/connection-between-h-and-m-files-in-objective-c-eaf6b7366717

@interface CrashOps()

@property (nonatomic, strong) NSDictionary *environmentConfigurations;
//@property (nonatomic, assign) SCEnvironment currentEnvironment;

@end

@implementation CrashOps

@synthesize clientId;
@synthesize metadata;
@synthesize isEnabled;

- (instancetype)init {
    self = [super init];
    if (self) {
        isEnabled = YES;
        clientId = @"";
        metadata = [NSMutableDictionary new];
    }

    return self;
}

- (void)deleteOldReports {
    [[KSCrash sharedInstance] deleteAllReports];
}

- (void)throwException {
    [NSException raise:@"CrashOps test exception" format: @""];
}

- (BOOL) logError:(NSDictionary *)errorDetails {
    return [((CrashOpsController *)([CrashOpsController performSelector: @selector(shared)])) logError: errorDetails];
}

- (void)crash {
    [self performSelector:@selector(callUnimplementedSelector)];
}

// Singleton implementation in Objective-C
__strong static CrashOps *_sharedInstance;
+ (CrashOps *)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[CrashOps alloc] init];
    });
    
    return _sharedInstance;
}

- (void)setPreviousCrashReports:(PreviousReportsHandler) handler {
    _previousCrashReports = handler;

    [((CrashOpsController *)([CrashOpsController performSelector: @selector(shared)])) onChangedHandler];
}

- (void)setClientId:(NSString *)crashOpsClientId {
    if (![crashOpsClientId length]) {
        return;
    }

    if ([crashOpsClientId length] > 100) {
        return;
    }

    clientId = crashOpsClientId;
    ((CrashOpsController *)([CrashOpsController performSelector: @selector(shared)])).clientId = clientId;
}

- (void)setIsEnabled:(BOOL)isOn {
    isEnabled = isOn;
    ((CrashOpsController *)([CrashOpsController performSelector: @selector(shared)])).isEnabled = isOn;
}

+ (CrashOps *)shared {
    return [CrashOps sharedInstance];
}

+ (void)load {
    NSLog(@"Class loaded");
}

+(void)initialize {
    NSLog(@"App loaded");
}

@end
