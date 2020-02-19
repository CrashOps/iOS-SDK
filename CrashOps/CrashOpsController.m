//
//  CrashOpsController.m
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "CrashOps.h"
#import "CrashOpsController.h"
#import "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor.h"
#include "KSCrashMonitorContext.h"
#import <KZCrash/KSCrash.h>
#import <KZCrash/KSCrashInstallationStandard.h>
#import <KZCrash/KSCrashInstallationConsole.h>
#import <KZCrash/KSCrashInstallationEmail.h>
#import <sys/utsname.h>

#import <AdSupport/ASIdentifierManager.h>

typedef void(^ReportsUploadCompletion)(NSArray *reports);

@interface CrashOpsController()

@property (nonatomic, strong) NSString *libraryPath;
@property (nonatomic, strong) NSObject *appFinishedLaunchObserver;
@property (nonatomic, strong) NSNumber *isEnabled_Optional;
@property (nonatomic) NSOperationQueue* coGlobalOperationQueue;
@property (nonatomic, assign) KSCrashMonitorAPI* crashMonitorAPI;
@property (nonatomic, assign) BOOL didAppFinishLaunching;
@property (nonatomic, assign) BOOL didBeginUpload;

@end

@implementation CrashOpsController

@synthesize libraryPath;
@synthesize appFinishedLaunchObserver;
@synthesize coGlobalOperationQueue;
@synthesize isEnabled;
@synthesize isEnabled_Optional;
@synthesize didAppFinishLaunching;
@synthesize didBeginUpload;
@synthesize crashMonitorAPI;
@synthesize clientId;

NSUncaughtExceptionHandler *oldHandler;

// Singleton implementation in Objective-C
__strong static CrashOpsController *_shared;
+ (CrashOpsController *) shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CrashOpsController alloc] init];
    });
    
    return _shared;
}

- (id)init {
    if (self = [super init]) {
        coGlobalOperationQueue = [[NSOperationQueue alloc] init];
        didBeginUpload = NO;
        isEnabled = YES;
    }

    return self;
}

/**
 Using conditional compilation flags: https://miqu.me/blog/2016/07/31/xcode-8-new-build-settings-and-analyzer-improvements/
 */
+(BOOL)isRunningInDebugMode {
#ifdef DEBUG
    return YES;
#else
    return NO;
#endif
}

// That's new to me, taken from: https://medium.com/@pinmadhon/how-to-check-your-app-is-installed-on-a-jailbroken-device-67fa0170cf56
+(BOOL)isJailbroken {
    BOOL isJailbroken = NO;
#if !(TARGET_IPHONE_SIMULATOR)
    // Check 1 : existence of files that are common for jailbroken devices
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/Cydia.app"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/Library/MobileSubstrate/MobileSubstrate.dylib"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/bin/bash"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/sbin/sshd"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/etc/apt"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/lib/apt/"] ||
        [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"cydia://package/com.example.package"]]) {
        isJailbroken |= YES;
    }
    FILE *f = NULL ;
    if ((f = fopen("/bin/bash", "r")) ||
        (f = fopen("/Applications/Cydia.app", "r")) ||
        (f = fopen("/Library/MobileSubstrate/MobileSubstrate.dylib", "r")) ||
        (f = fopen("/usr/sbin/sshd", "r")) ||
        (f = fopen("/etc/apt", "r"))) {
        fclose(f);
        isJailbroken |= YES;
    }
    fclose(f);
    // Check 2 : Reading and writing in system directories (sandbox violation)
    NSError *error;
    NSString *stringToBeWritten = @"Jailbreak Test.";
    [stringToBeWritten writeToFile:@"/private/jailbreak.txt" atomically:YES
                          encoding:NSUTF8StringEncoding error:&error];
    if(error==nil) {
        //Device is jailbroken
        isJailbroken |= YES;
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:@"/private/jailbreak.txt" error:nil];
    }
#endif
    return isJailbroken;
}

+(BOOL)isRunningOnSimulator {
#if TARGET_IPHONE_SIMULATOR
    return YES;
#else
    return NO;
#endif
}

- (void)onChangedHandler {
    [self uploadLogs];
}

- (void)setClientId:(NSString *)crashOpsClientId {
    if (![crashOpsClientId length]) {
        return;
    }

    if ([crashOpsClientId length] > 100) {
        return;
    }

    clientId = crashOpsClientId;

    [self uploadLogs];
}

- (void) setIsEnabled:(BOOL)isOn {
    if (isEnabled_Optional != nil && isEnabled == isOn) return;

    isEnabled = isOn;
    isEnabled_Optional = [NSNumber numberWithBool: isOn];

    if (isOn) {
        if (crashMonitorAPI == nil) {
            crashMonitorAPI = kscm_nsexception_getAPI();
            if (NSGetUncaughtExceptionHandler() != exceptionHandlerPtr) {
                oldHandler = NSGetUncaughtExceptionHandler();
                NSSetUncaughtExceptionHandler(exceptionHandlerPtr);
            }

            [self configureAdvancedSettings];

            if ([CrashOps shared].isEnabled) {
                KSCrashInstallationStandard* installation = [KSCrashInstallationStandard sharedInstance];
                [installation install];
            }

            /* Perry's additions to help with tests */
            crashMonitorAPI->setEnabled(YES);
            /* Perry's additions to help with tests */
        }

        [self uploadLogs];
    } else {
        if (oldHandler != nil) {
            NSSetUncaughtExceptionHandler(oldHandler);
        }

        if (crashMonitorAPI != nil) {
            crashMonitorAPI->setEnabled(NO);
        }
    }
}

- (BOOL) logError:(NSDictionary *) errorDetails {
    if (!errorDetails) return NO;
    if (![errorDetails count]) return NO;

    NSTimeInterval timeMilliseconds = [[NSDate date] timeIntervalSince1970] * 1000;
    NSInteger timestamp = ((NSInteger) timeMilliseconds);
    NSString *basePath = [[KSCrash sharedInstance] performSelector: @selector(basePath)];
    NSString *reportsPath = [basePath stringByAppendingPathComponent: @"Errors"];
    NSString *filePath = [reportsPath stringByAppendingPathComponent: [NSString stringWithFormat:@"error_%ld.log", (long) timestamp]];

    NSData *errorData = [NSKeyedArchiver archivedDataWithRootObject: errorDetails];
    return [errorData writeToFile: filePath atomically: YES];
}

-(void) onAppLoaded {
    // Wait for app to finish launch and then...
    appFinishedLaunchObserver = [[NSNotificationCenter defaultCenter] addObserverForName: UIApplicationDidFinishLaunchingNotification object: nil queue: nil usingBlock:^(NSNotification * _Nonnull note) {
        [CrashOpsController shared].didAppFinishLaunching = YES;
        [[CrashOpsController shared] onAppLaunched];
    }];

    NSString *infoPlistPath = [[NSBundle mainBundle] pathForResource:@"CrashOpsConfig-info" ofType:@"plist"];
    NSDictionary* infoPlist = [NSDictionary dictionaryWithContentsOfFile: infoPlistPath];

    NSString* clientId = infoPlist[@"clientId"];
    if (clientId == nil) {
        clientId = @"";
    }

    NSString* isDisabledOnRelease = infoPlist[@"isDisabledOnRelease"];
    if (isDisabledOnRelease == nil) {
        isDisabledOnRelease = @"0";
    }
    BOOL config_isDisabledOnRelease = isDisabledOnRelease.boolValue;

    NSString* isDisabledOnDebug = infoPlist[@"isDisabledOnDebug"];
    if (isDisabledOnDebug == nil) {
        isDisabledOnDebug = @"0";
    }
    BOOL config_isDisabledOnDebug = isDisabledOnDebug.boolValue;

    NSString* isEnabledString = infoPlist[@"isEnabled"];
    if (isEnabledString == nil) {
        isEnabledString = @"1";
    }
    BOOL config_isEnabled = isEnabledString.boolValue;

    BOOL isEnabled = config_isEnabled;
    
    if (CrashOpsController.isRunningInDebugMode && config_isDisabledOnDebug) {
        isEnabled = NO;
    }

    if (!CrashOpsController.isRunningInDebugMode && config_isDisabledOnRelease) {
        isEnabled = NO;
    }

    [CrashOps shared].isEnabled = isEnabled;
    [CrashOps shared].clientId = clientId;
}

- (void) onAppLaunched {
    [[NSNotificationCenter defaultCenter] removeObserver: [[CrashOpsController shared] appFinishedLaunchObserver]];

    //NSLog(@"App loaded, isJailbroken = %d", CrashOpsController.isJailbroken);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[CrashOpsController shared] uploadLogs];
    });
}

// ======================================================================
#pragma mark - Advanced Crash Handling (optional) -
// ======================================================================
- (void) uploadLogs {
    if (![CrashOps shared].isEnabled) return;
//    if (didBeginUpload) return;
    didBeginUpload = true;

    if ([[KSCrash sharedInstance] respondsToSelector: @selector(basePath)]) {
        NSString *basePath = [[KSCrash sharedInstance] performSelector: @selector(basePath)];
        NSString *reportsPath = [basePath stringByAppendingPathComponent: @"Reports"];
        
        [[[CrashOpsController shared] coGlobalOperationQueue] addOperationWithBlock:^{
            NSString *clientId = CrashOps.shared.clientId;
            if (!(clientId && [clientId length] > 0 && [clientId length] < 100)) {
                clientId = nil;
            }

            if ([[NSFileManager defaultManager] fileExistsAtPath: reportsPath]) {
                NSArray *filesList = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString: reportsPath] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];

                NSMutableDictionary *allReports = [NSMutableDictionary new];

                for (NSURL *logFileUrlPath in filesList) {
                    NSLog(@"%@", logFileUrlPath);

                    NSString *logFileJson = [[NSString alloc] initWithData: [NSData dataWithContentsOfURL: logFileUrlPath] encoding: NSUTF8StringEncoding];
                    [allReports setObject:logFileJson forKey:logFileUrlPath];
                }

                NSMutableArray *uploadTasks = [NSMutableArray new];
                // An old fashion, simplified, "synchronizer" :)
                ReportsUploadCompletion completion = ^void(NSArray* reportPaths) {
                    if ([reportPaths count] > 0 && [CrashOps shared].previousCrashReports) {
                        if (![CrashOps shared].isEnabled) return;

                        NSMutableArray* reportDictionaries = [NSMutableArray new];
                        for (NSURL *reportPath in allReports) {
                            NSString *reportJson = allReports[reportPath];

                            if (reportJson) {
                                NSDictionary *jsonDictionary = [CrashOpsController toJsonDictionary: reportJson];

                                [reportDictionaries addObject: jsonDictionary];
                                NSError *error;
                                [[NSFileManager defaultManager] removeItemAtURL: reportPath error: &error];
                                if (error) {
                                    // TODO: Report this to our private analytics tool
                                    NSLog(@"Failed to delete report file, error: %@", error);
                                }
                            }
                        }

                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                            [CrashOps shared].previousCrashReports(reportDictionaries);
                        }];
                    } else if ([reportPaths count] > 0) {
                        // Considered waiting to the first VC to appear (https://spin.atomicobject.com/2014/12/30/method-swizzling-objective-c/) but it's also won't solve all cases by the various developers out there.

                        NSLog(@"Waiting to the host app's handler to be set...");
//                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                            [[CrashOpsController shared] uploadLogs]; // Bad solution, we won't use this solution for example...
//                        });
                    }
                };

                NSMutableArray *sentReports = [NSMutableArray new];
                NSString *serverUrlString = @"https://us-central1-crash-logs.cloudfunctions.net/storeCrashReport";

                for (NSURL *reportPath in allReports) {
                    NSString *reportJson = allReports[reportPath];
                    if (clientId) {
                        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
                        [request setURL:[NSURL URLWithString: serverUrlString]];
                        [request setHTTPMethod: @"POST"];

                        NSMutableData *body = [NSMutableData data];

                        NSString *contentType = [NSString stringWithFormat:@"application/json; charset=utf-8"];
                        [request addValue:contentType forHTTPHeaderField:@"Content-Type"];
                        [request addValue: clientId forHTTPHeaderField:@"crashops-client-id"];

                        [body appendData:[[NSString stringWithString: reportJson] dataUsingEncoding: NSUTF8StringEncoding]];

                        [request setHTTPBody: body];

                        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request completionHandler:^(NSData * _Nullable returnedData, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                            NSString *returnString = [[NSString alloc] initWithData: returnedData encoding: NSUTF8StringEncoding];
                            NSLog(@"%@", returnString);

                            BOOL wasRequestSuccessful = false;
                            if (response && [response isKindOfClass:[NSHTTPURLResponse class]]) {
                                wasRequestSuccessful = ((NSHTTPURLResponse *)response).statusCode > 200 && ((NSHTTPURLResponse *)response).statusCode < 300;
                            }

                            if (wasRequestSuccessful) {
                                [sentReports addObject: reportPath];
                            }

                            [uploadTasks removeLastObject];
                            if (uploadTasks.count == 0) {
                                completion(sentReports);
                            }
                        }];

                        [uploadTasks addObject: task];
                    } else {
                        NSDictionary *jsonDictionary = [CrashOpsController toJsonDictionary: reportJson];
                        [sentReports addObject: jsonDictionary];
                    }
                }
                
                if (!clientId) {
                    completion(sentReports);
                }

                for (NSURLSessionDataTask *uploadTask in uploadTasks) {
                    [uploadTask resume];
                }
            }
        }];
    }
}

- (void) configureAdvancedSettings {
    KSCrash* handler = [KSCrash sharedInstance];

    NSDictionary *metadata;
    if ([CrashOps shared].metadata && [[CrashOps shared].metadata count]) {
        metadata = [[CrashOps shared].metadata copy];
    } else {
        metadata = [NSDictionary new];
    }

    handler.userInfo = @{@"hostAppInfo": metadata, @"deviceInfo": [CrashOpsController getDeviceInfo]};
    
    if ([CrashOps shared].excludeClassesDetails) {
        // Do not introspect these classes
        handler.doNotIntrospectClasses = [[CrashOps shared].excludeClassesDetails copy];
    }
}

-(void) handleException:(NSException *) exception {
    if (oldHandler) {
        oldHandler(exception);
    }

    if ([CrashOps shared].isEnabled) {
        NSMutableDictionary *jsonReport = [NSMutableDictionary new];

        NSThread *current = [NSThread currentThread];
        [jsonReport setObject: [current description] forKey: @"crashedThread"];

        [jsonReport setObject: exception.callStackSymbols forKey: @"stackTrace"];
        [jsonReport setObject: exception.reason forKey: @"reason"];
        if (exception.userInfo) {
            [jsonReport setObject: exception.userInfo forKey: @"moreInfo"];
        }

        [jsonReport setObject: CrashOps.shared.metadata forKey: @"metadata"];

        NSTimeInterval now = [[NSDate date] timeIntervalSince1970] * 1000;
        long timestamp = (long) now;
        NSString *nowString = [NSString stringWithFormat: @"crash-log-%ld.json", timestamp];

        NSError *error;

        NSString *toJsonString = [CrashOpsController toJsonString: jsonReport];
        NSLog(@"%@", toJsonString);

        NSData *jsonData = [CrashOpsController toJsonData: jsonReport];

        BOOL didWrite = [jsonData writeToFile: [[self crashOpsLibraryPath] stringByAppendingPathComponent: nowString] options: NSDataWritingAtomic error: &error];
        if (!didWrite || error) {
            NSLog(@"Failed to save with error %@", error);
        } else {
            NSLog(@"Saved :)");
        }

        NSLog(@"Send log to CrashOps server on next app launch... ");
    }
    
    if ([CrashOps shared].appExceptionHandler) {
        [CrashOps shared].appExceptionHandler(exception);
    }
}

-(NSString *) crashOpsLibraryPath {
    if (libraryPath != nil) {
        return libraryPath;
    }

    NSString *path = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent: @"CrashOps"];

    BOOL isDir = YES;
    NSFileManager *fileManager= [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir])
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL])
            NSLog(@"Error: Create folder failed %@", path);


    libraryPath = path;

    return libraryPath;
}

static void ourExceptionHandler(NSException *exception) {
    [[CrashOpsController shared] handleException: exception];
}

+(NSString *) toJsonString:(NSDictionary *) jsonDictionary {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject: jsonDictionary options: NSJSONWritingPrettyPrinted error: &error];

    NSString* jsonString = [[NSString alloc] initWithData: jsonData encoding: NSUTF8StringEncoding];
    NSLog(@"jsonString: %@", jsonString);
    
    return error ? nil : jsonString;
}

+(NSData *) toJsonData:(NSDictionary *) jsonDictionary {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject: jsonDictionary options: NSJSONWritingPrettyPrinted error: &error];

    return jsonData;
}

+(NSDictionary *) toJsonDictionary:(NSString *) jsonString {
    NSError *jsonError;
    NSData *objectData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *jsonDictionary = [NSJSONSerialization JSONObjectWithData: objectData
                                          options: NSJSONReadingMutableContainers
                                            error: &jsonError];

    return jsonDictionary;
}

NSUncaughtExceptionHandler *exceptionHandlerPtr = &ourExceptionHandler;

+ (void)load {
    [[CrashOpsController shared] onAppLoaded];
}

+(void)initialize {
    NSLog(@"App loaded");
}

+ (NSDictionary *) getDeviceInfo {
    UIDevice* device = [UIDevice currentDevice];
    struct utsname un;
    uname(&un);

    // Discussion: These two strings are different...
//    NSLog([CrashOpsController advertisingIdentifierString]);
//    NSLog([[device identifierForVendor] UUIDString]);

    return @{
      @"name" : [device name],
      @"systemName" : [device systemName],
      @"systemVersion" : [device systemVersion],
      @"model" : [device model],
      @"localizedModel" : [device localizedModel],
      @"identifierForVendor" : [[device identifierForVendor] UUIDString],
      @"isPhysicalDevice" : CrashOpsController.isRunningOnSimulator ? @"false" : @"true",
      @"utsname" : @{
        @"sysname" : @(un.sysname),
        @"nodename" : @(un.nodename),
        @"release" : @(un.release),
        @"version" : @(un.version),
        @"machine" : @(un.machine),
      }
    };
}

+ (NSString *) advertisingIdentifierString {
    return [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
}

@end
