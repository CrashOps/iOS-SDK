//
//  CrashOpsController.m
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "CrashOps.h"
#import "CrashOpsController.h"
#import "DebugToastMessage.h"

#import "AppleCrashReportGenerator.h"

#import "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor.h"
#include "KSCrashMonitorContext.h"
#import <KZCrash/KSCrash.h>
#import <KZCrash/KSCrashInstallationStandard.h>
#import <KZCrash/KSCrashInstallationConsole.h>
#import <sys/utsname.h>

#import <objc/runtime.h>
#import <zlib.h>

#import "CrashOpsExtendedViewController+UIViewController.h"

typedef void(^FilesUploadCompletion)(NSInteger filesCount);

typedef void(^LogsUploadCompletion)(NSArray *reports);

@interface CrashOpsController()

@property (nonatomic, strong) NSString *appSessionId;
@property (nonatomic, strong) NSUserDefaults *coUserDefaults;
@property (nonatomic, strong) NSString *libraryPath;
@property (nonatomic, strong) NSString *errorsPath;
@property (nonatomic, strong) NSString *tracesPath;
@property (nonatomic, strong) NSString *currentTracesPath;
@property (nonatomic, strong) NSString *eventsPath;
@property (nonatomic, strong) NSString *sessionsPath;
@property (nonatomic, strong) NSString *ipsFilesPath;
@property (nonatomic, strong) NSObject *appFinishedLaunchObserver;
@property (nonatomic, strong) NSNumber *isEnabled_Optional;
@property (nonatomic, strong) NSNumber *isJailbroken_Optional;

@property (nonatomic, strong) NSArray *previousErrorLogFilesList;
@property (nonatomic, strong) NSArray *previousCrashLogFilesList;

/// This is the SDK's main queue, it used for several reasons. It provides smoother UI experience plus handles collections safely to avoid concurrent modifications.
@property (nonatomic) NSOperationQueue* coGlobalOperationQueue;
@property (nonatomic, assign) KSCrashMonitorAPI* crashMonitorAPI;
@property (nonatomic, assign) BOOL didAppFinishLaunching;
@property (nonatomic, assign) BOOL isUploading;
@property (nonatomic, assign) BOOL didSendPresence;
@property (nonatomic, assign) BOOL isDebugModeEnabled;

@property (nonatomic, strong) ScreenTracer *screenTracer;

+(void) logInternalError:(NSString *) internalError;

@end

#define DebugLog(msg) if (CrashOpsController.isDebugModeEnabled) { NSLog(@"[CrashOps] %@", msg); }
#define DebugLogArgs(msg, args) if (CrashOpsController.isDebugModeEnabled) { NSLog(@"[CrashOps] %@", [NSString stringWithFormat: msg, args]); }

#define COAssertToast(condition, message) COAssert(condition, message, YES)

#define COAssertLog(condition, message) COAssert(condition, message, NO)

#define COAssert(condition, message, shouldToast)    \
    if (__builtin_expect(!(condition), 0)) {        \
        if (shouldToast)\
            [co_ToastMessage show: [NSString stringWithFormat:@"Assertion Error!\n%@", message] delayInSeconds: 2 onDone: nil]; \
            NSLog(@"Assertion Error!\n%@", message); \
    }

@implementation CrashOpsController

/** Date formatter for Apple date format in crash reports. */
static NSDateFormatter* g_dateFormatter;
static NSString * const kAppKey = @"co_AppKey";
static NSString * const kSdkIdentifier = @"com.crashops.sdk";
static NSString * const kSdkName = @"CrashOps";

@synthesize appSessionId;
@synthesize coUserDefaults;
@synthesize libraryPath;
@synthesize errorsPath;
@synthesize tracesPath;
@synthesize currentTracesPath;
@synthesize eventsPath;
@synthesize sessionsPath;
@synthesize appFinishedLaunchObserver;
@synthesize coGlobalOperationQueue;
@synthesize isEnabled;
@synthesize isEnabled_Optional;
@synthesize isJailbroken_Optional;
@synthesize didAppFinishLaunching;
@synthesize isUploading;
@synthesize didSendPresence;
@synthesize crashMonitorAPI;
@synthesize appKey;
//@synthesize screenTracer;
@synthesize isDebugModeEnabled;

NSUncaughtExceptionHandler *co_oldHandler;

// Singleton implementation in Objective-C
__strong static CrashOpsController *_shared;
+ (CrashOpsController *) shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CrashOpsController alloc] initWithCoder: nil];
    });
    
    return _shared;
}

- (instancetype)init {
    return [CrashOpsController shared];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        coGlobalOperationQueue = [[NSOperationQueue alloc] init];
        coGlobalOperationQueue.name = kSdkIdentifier;
        isUploading = NO;
        isDebugModeEnabled = NO;
        isEnabled = YES;
        didSendPresence = NO;
        coUserDefaults = [[NSUserDefaults alloc] initWithSuiteName: kSdkIdentifier];
        _screenTracer = [ScreenTracer new];
        appSessionId = [[NSUUID UUID] UUIDString];
    }

    return self;
}

/**
 Using conditional compilation flags: https://miqu.me/blog/2016/07/31/xcode-8-new-build-settings-and-analyzer-improvements/
 */

// That's new to me, taken from: https://medium.com/@pinmadhon/how-to-check-your-app-is-installed-on-a-jailbroken-device-67fa0170cf56
-(BOOL)isJailbroken {
    if (isJailbroken_Optional) {
        return [isJailbroken_Optional boolValue];
    }

    BOOL _isJailbroken = NO;
#if !(TARGET_IPHONE_SIMULATOR)
    // Check 1 : existence of files that are common for jailbroken devices
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/Cydia.app"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/Library/MobileSubstrate/MobileSubstrate.dylib"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/bin/bash"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/sbin/sshd"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/etc/apt"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/lib/apt/"] ||
        [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"cydia://package/com.example.package"]]) {
        _isJailbroken |= YES;
    }
    FILE *f = NULL ;
    if ((f = fopen("/bin/bash", "r")) ||
        (f = fopen("/Applications/Cydia.app", "r")) ||
        (f = fopen("/Library/MobileSubstrate/MobileSubstrate.dylib", "r")) ||
        (f = fopen("/usr/sbin/sshd", "r")) ||
        (f = fopen("/etc/apt", "r"))) {
        fclose(f);
        _isJailbroken |= YES;
    }
    fclose(f);
    // Check 2 : Reading and writing in system directories (sandbox violation)
    NSError *error;
    NSString *stringToBeWritten = @"Jailbreak Test.";
    [stringToBeWritten writeToFile:@"/private/jailbreak.txt" atomically:YES
                          encoding:NSUTF8StringEncoding error:&error];
    if(error == nil) {
        //Device is jailbroken
        _isJailbroken |= YES;
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:@"/private/jailbreak.txt" error:nil];
    }
#endif
    isJailbroken_Optional = [NSNumber numberWithBool: _isJailbroken];
    return [isJailbroken_Optional boolValue];
}

+(BOOL)isRunningOnSimulator {
#if TARGET_IPHONE_SIMULATOR
    return YES;
#else
    return NO;
#endif
}

+ (BOOL)isDebugModeEnabled {
    return _shared.isDebugModeEnabled;
}

- (void)onHandlerChanged {
    [self uploadLogs];
}

- (void)setAppKey:(NSString *)crashOpsAppKey {
    // https://stackoverflow.com/questions/899209/how-do-i-test-if-a-string-is-empty-in-objective-c
    if (![crashOpsAppKey length]) {
        return;
    }

    if ([crashOpsAppKey length] > 100) {
        return;
    }

    if (![appKey length]) {
        appKey = crashOpsAppKey;
        [[self coUserDefaults] setObject: appKey forKey: kAppKey];
    } else {
        // TODO: Notify that application's key has already been set.
    }

    if ([appKey length]) {
        [self uploadLogs];
    }
}

- (NSString *) sessionId {
    return [[CrashOpsController shared] appSessionId];
}

- (void) setIsEnabled:(BOOL)isOn {
    if (isEnabled_Optional != nil && isEnabled == isOn) return;

    isEnabled = isOn;
    isEnabled_Optional = [NSNumber numberWithBool: isOn];
    
    [self setupIfNeeded];
}

- (void) setupIfNeeded {
    if (isEnabled) {
        if (crashMonitorAPI == nil) {
            crashMonitorAPI = kscm_nsexception_getAPI();
            if (NSGetUncaughtExceptionHandler() != exceptionHandlerPtr) {
                co_oldHandler = NSGetUncaughtExceptionHandler();
                NSSetUncaughtExceptionHandler(exceptionHandlerPtr);
            }

            [self configureAdvancedSettings];

            if ([CrashOps shared].isEnabled) {
                KSCrashInstallationStandard* installation = [KSCrashInstallationStandard sharedInstance];
                [installation install];
            }

            crashMonitorAPI->setEnabled(YES);
        }

        [self sendPresence];
        [self uploadLogs];
    } else {
        if (co_oldHandler != nil) {
            NSSetUncaughtExceptionHandler(co_oldHandler);
        }

        if (crashMonitorAPI != nil) {
            crashMonitorAPI->setEnabled(NO);
        }
    }
}

+ (void) logLibraryError:(NSError *) errorObject {
    [CrashOpsController logInternalError: [NSString stringWithFormat:@"%@ encountered NSError, details: %@", kSdkName, [errorObject description]]];
}

+ (void) logInternalError:(NSString *) sdkError {
    DebugLogArgs(@"%@", sdkError);
    //[co_ToastMessage show: sdkError delayInSeconds: 2 onDone: nil];
    [[CrashOpsController shared] reportInternalError: sdkError];
}

// TODO: Report to our dedicated analytics tool
- (void)reportInternalError:(NSString *) sdkError {
    //TODO: Add to report JSON: app key + device info (storage status, device model, iOS version, etc.)
}

-(void) onAppIsLoading {
    // Wait for app to finish launch and then...
    appFinishedLaunchObserver = [[NSNotificationCenter defaultCenter] addObserverForName: UIApplicationDidFinishLaunchingNotification object: nil queue: nil usingBlock:^(NSNotification * _Nonnull note) {
        [CrashOpsController shared].didAppFinishLaunching = YES;
        [[CrashOpsController shared] onAppLaunched];
    }];
}

- (void) onAppLaunched {
    [UIViewController swizzleScreenAppearance];

    [[NSNotificationCenter defaultCenter] removeObserver: [[CrashOpsController shared] appFinishedLaunchObserver]];

    [[self coGlobalOperationQueue] addOperationWithBlock:^{
        [CrashOpsController shared].appKey = [[[CrashOpsController shared] coUserDefaults] stringForKey: kAppKey];

        [[CrashOpsController shared] setupFromInfoPlist];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[CrashOpsController shared] runTests];
        });
    }];

    //DebugLogArgs(@"App loaded, isJailbroken = %d", CrashOpsController.isJailbroken);
}

-(void) sendPresence {
    if (!isEnabled) return;
    if (![[CrashOpsController shared].appKey length]) return;

    if (didSendPresence) return;
    didSendPresence = YES;

    NSUInteger timestamp = (NSUInteger)_timestamp_milliseconds();

    NSMutableDictionary *deviceInfo = [[CrashOpsController getDeviceInfo] mutableCopy];
    NSDictionary *ksCrashSystemInfo = [[KSCrash sharedInstance] systemInfo];

    if ([ksCrashSystemInfo count]) {
        NSArray *keys = @[@"cpuType", @"cpuSubType", @"cpuArchitecture", @"storageSize", @"memorySize", @"usableMemory", @"freeMemory", @"kernelVersion", @"isJailbroken"];
        for (NSString *key in keys) {
            BOOL didAdd = [deviceInfo
             co_setOptionalObject: [ksCrashSystemInfo objectForKey: key]
             forKey: key];

            if (!didAdd) {
                DebugLog(@"Hmmmm...");
            }
        }
    }

    NSDictionary *sessionDetails = @{@"sessionId": appSessionId,
                                     @"timestamp": [NSString stringWithFormat:@"%lu", (unsigned long) timestamp],
                                     @"sdkVersion": [CrashOps sdkVersion],
                                     @"deviceId": [CrashOpsController deviceId],
                                     @"devicePlatform": @"ios",
                                     @"deviceInfo": deviceInfo,
                                     @"crashopsApplicationKey": [CrashOpsController shared].appKey,
                                     @"iosVersion": [CrashOpsController iosVersion],
    };

    NSMutableURLRequest *request = [CrashOpsController prepareRequestWithBody: sessionDetails forEndpoint: @"ping"];

    if (!request) {
        [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to make request for sending ping: %@", sessionDetails]];
        return;
    }

    [request addValue: appKey forHTTPHeaderField:@"crashops-application-key"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request completionHandler:^(NSData * _Nullable returnedData, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSString *responseString = [[NSString alloc] initWithData: returnedData encoding: NSUTF8StringEncoding];
        DebugLogArgs(@"%@", responseString);

        BOOL wasRequestSuccessful = false;
        NSInteger responseStatusCode = 100;
        if (response && [response isKindOfClass: [NSHTTPURLResponse class]]) {
            responseStatusCode = ((NSHTTPURLResponse *)response).statusCode;
            wasRequestSuccessful = responseStatusCode >= 200 && responseStatusCode < 300;
        }

        [[self coGlobalOperationQueue] addOperationWithBlock:^{
            if (wasRequestSuccessful) {
                if (responseStatusCode == 202) {
                    DebugLogArgs(@"Accepted session details and saved. Details: %@", sessionDetails);
                }
            } else {
                if (responseStatusCode >= 400 && responseStatusCode < 500) {
                    // Integratoin error occured - deleting log anyway to avoid a large "history" folder size.
                    
                    if (responseStatusCode == 409) {
                        DebugLogArgs(@"This session already sent in the past, details: %@", sessionDetails);
                    } else {
                        DebugLogArgs(@"Some client error occurred for details: %@", sessionDetails);
                    }
                }
                
                [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to send session details, response string: %@, file path: %@", responseString, sessionDetails]];
            }
        }];
    }];

    [task resume];
}

-(void) setupFromInfoPlist {
    NSString *infoPlistPath = [[NSBundle mainBundle] pathForResource:@"CrashOpsConfig-info" ofType:@"plist"];
    NSDictionary* infoPlist = [NSDictionary dictionaryWithContentsOfFile: infoPlistPath];
    if (!infoPlist) {
        infoPlist = @{};
    }

    NSString* appKey = infoPlist[@"APPLICATION_KEY"];

    NSString* isDisabledOnRelease = infoPlist[@"IS_DISABLED_ON_RELEASE"];
    if (isDisabledOnRelease == nil) {
        isDisabledOnRelease = @"0";
    }
    BOOL config_isDisabledOnRelease = isDisabledOnRelease.boolValue;

    NSString* isTracingScreens = infoPlist[@"IS_TRACING_SCREENS"];

    NSString* _isDebugModeEnabled = infoPlist[@"IS_DEBUG_MODE_ENABLED"];
    if (_isDebugModeEnabled == nil) {
        _isDebugModeEnabled = @"0";
    }
    self.isDebugModeEnabled = _isDebugModeEnabled.boolValue;

    NSString* isDisabledOnDebug = infoPlist[@"IS_DISABLED_ON_DEBUG"];
    if (isDisabledOnDebug == nil) {
        isDisabledOnDebug = @"0";
    }
    BOOL config_isDisabledOnDebug = isDisabledOnDebug.boolValue;

    NSString* isEnabledString = infoPlist[@"IS_ENABLED"];

    if (CrashOps.isRunningOnDebugMode && config_isDisabledOnDebug) {
        isEnabled = NO;
    }

    if (!CrashOps.isRunningOnDebugMode && config_isDisabledOnRelease) {
        isEnabled = NO;
    }

    if (isEnabledString != nil) {
        BOOL config_isEnabled = isEnabledString.boolValue;
        [CrashOps shared].isEnabled = config_isEnabled;
    }

    if (isTracingScreens != nil) {
        BOOL config_isTracingScreens = isTracingScreens.boolValue;
        [CrashOps shared].isTracingScreens = config_isTracingScreens;
    }

    if (appKey != nil) {
        [CrashOps shared].appKey = appKey;
    }

    [self setupIfNeeded];
}

-(void)runTests {
    if (!isDebugModeEnabled) return;

    COAssert([CrashOpsController toJsonDictionary: @""].count == 0, @"empty strings should become empty dictionaries", YES);
    
    COAssert([CrashOpsController toJsonDictionary: nil].count == 0, @"nil strings should become empty dictionaries", YES);

    NSData *screenTracesData = [CrashOpsController toJsonData: @{@"screenTraces": @[]}];
    NSString *screenTracesJsonString = [CrashOpsController toJsonString: @{@"screenTraces": @[]}];
    COAssert(screenTracesData != nil, @"nil strings should become empty dictionaries", NO);
    COAssert(screenTracesJsonString != nil, @"nil strings should become empty dictionaries", NO);
    
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        BOOL didCatch = NO;
//        @try {
//            [NSJSONSerialization JSONObjectWithData: nil options: NSJSONReadingMutableContainers error: nil];
//            NSInteger stam = @[@1,@2,@3,@4][8];
//        } @catch (NSException *exception) {
//            didCatch = YES;
//            DebugLog([exception.name description]);
//        } @finally {
//            // ignore
//        }
//
//        COAssert(didCatch, @"Didn't catch obvious exception");
//    });

    COAssert([CrashOpsController toJsonData: nil].length == 0, @"Empty strings should become empty data", NO);
    
    NSString *infoPlistPath = [[NSBundle mainBundle] pathForResource:@"CrashOpsConfig-info" ofType:@"plist"];
    
    NSURL *plistFilePathUrl = [NSURL URLWithString: infoPlistPath];
    NSURL *nonExistingFilePathUrl = [NSURL URLWithString: [infoPlistPath stringByReplacingOccurrencesOfString:[infoPlistPath lastPathComponent] withString:@"CrashOpsConfig-info.xml"]];

    // This should return an empty dictionary becuase none of these paths contain JSON representations
    NSMutableDictionary *filesToUpload = [self prepareCrashLogsToUpload: @[plistFilePathUrl, nonExistingFilePathUrl]];
    COAssert(filesToUpload.count == 0, @"Expected files list to be empty!", YES);
}

- (NSArray *) errorLogFilesList {
    NSString *appKey = CrashOps.shared.appKey;
    if (!(appKey && [appKey length] > 0 && [appKey length] < 100)) {
        appKey = nil;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath: [self errorsFolderPath]]) {
        NSArray *filesList = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString: [self errorsFolderPath]] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];
        return filesList;
    }

    return @[];
}

- (NSArray *) crashLogFilesList {
    NSString *basePath = [KSCrash sharedInstance].basePath;
    NSString *reportsPath = [basePath stringByAppendingPathComponent: @"Reports"];

    if ([[NSFileManager defaultManager] fileExistsAtPath: reportsPath]) {
        NSArray *filesList = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString: reportsPath] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];
        return filesList;
    }

    return @[];
}

// ======================================================================
#pragma mark - Advanced Crash Handling (optional) -
// ======================================================================

- (void) uploadCrashes:(FilesUploadCompletion) onDone {
    NSString *appKey = [CrashOpsController shared].appKey;
    if (!(appKey && [appKey length] > 0 && [appKey length] < 100)) {
        appKey = nil;
    }

    NSString *reportsPath = [self crashesFolderPath];

    if (reportsPath && [reportsPath length] && [[NSFileManager defaultManager] fileExistsAtPath: reportsPath]) {
        NSArray *filesList = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString: reportsPath] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];

        if (filesList.count == 0) {
            if (onDone) {
                onDone(0);
            }

            return;
        }

        NSMutableDictionary *allReports = [self prepareCrashLogsToUpload: filesList];

        if (allReports.count == 0) {
            if (onDone) {
                onDone(0);
            }

            return;
        }

        NSMutableArray *uploadTasks = [NSMutableArray new];
        NSMutableArray *tasksCounters = [NSMutableArray new];
        // An old fashion, simplified, promise.all(..) / Future.all(..) / "synchronizer" :)
        LogsUploadCompletion completion = ^void(NSArray* sentReportPaths) {
            if ([sentReportPaths count] > 0) {
                if (![CrashOps shared].isEnabled) {
                    if (onDone) {
                        onDone(0);
                    }

                    return;
                }

                NSMutableArray* reportDictionaries = [NSMutableArray new];
                for (NSURL *reportPath in sentReportPaths) {
                    NSDictionary *jsonDictionary = allReports[reportPath];

                    [reportDictionaries addObject: jsonDictionary];

                    if (appKey) {
                        // Delete this log because it was uploaded
                        NSString *eventId = [AppleCrashReportGenerator reportId: jsonDictionary];
                        [self cleanUpEventId: eventId andReportPath: reportPath];
                    }
                }

                if ([CrashOps shared].previousCrashReports) {
                    static dispatch_once_t onceToken;
                    dispatch_once(&onceToken, ^{
                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                            [CrashOps shared].previousCrashReports(reportDictionaries);
                        }];
                    });
                }
            }

            if (onDone) {
                onDone(sentReportPaths.count);
            }
        };

        if (![allReports count]) {
            completion(@[]);

            return;
        }

        NSMutableArray *sentReports = [NSMutableArray new];

        NSArray *reportsPaths = [allReports allKeys];
        for (NSURL *reportPath in reportsPaths) {
            NSMutableDictionary *jsonDictionary = allReports[reportPath];
            if (appKey) {
//                NSDate *logTime = [AppleCrashReportGenerator crashDate: jsonDictionary];
                //   the `eventId` is located under "report"->"id"
                NSString *eventId = [AppleCrashReportGenerator reportId: jsonDictionary];

                NSArray *allTraces = [ScreenTracer tracesReportForSessionId: [CrashOpsController sessionIdFromEventId: eventId]];

                if ([allTraces count]) {
                    [jsonDictionary co_setOptionalObject: allTraces forKey: @"screenTraces"];
                }

                NSMutableURLRequest *request = [CrashOpsController prepareRequestWithBody: jsonDictionary forEndpoint: @"reports"];

                if (!request) {
                    [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to make request for file upload, file path: %@", reportPath]];
                    continue;
                }

                [request addValue: appKey forHTTPHeaderField:@"crashops-application-key"];

                NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request completionHandler:^(NSData * _Nullable returnedData, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    NSString *responseString = [[NSString alloc] initWithData: returnedData encoding: NSUTF8StringEncoding];
                    DebugLogArgs(@"%@", responseString);

                    BOOL wasRequestSuccessful = false;
                    NSInteger responseStatusCode = 100;
                    if (response && [response isKindOfClass: [NSHTTPURLResponse class]]) {
                        responseStatusCode = ((NSHTTPURLResponse *)response).statusCode;
                        wasRequestSuccessful = responseStatusCode >= 200 && responseStatusCode < 300;
                    }

                    [[self coGlobalOperationQueue] addOperationWithBlock:^{
                        if (wasRequestSuccessful) {
                            if (responseStatusCode == 202) {
                                DebugLogArgs(@"Accepted log and saved, file: %@", reportPath);
                                [sentReports addObject: reportPath];
                            }
                        } else {
                            if (responseStatusCode >= 400 && responseStatusCode < 500) {
                                // Integratoin error occured - deleting log anyway to avoid a large "history" folder size.
                                [sentReports addObject: reportPath];
                                
                                if (responseStatusCode == 409) {
                                    DebugLogArgs(@"This log that already sent in the past, file: %@", reportPath);
                                } else {
                                    DebugLogArgs(@"Some client error occurred for file: %@", reportPath);
                                }
                            }
                            
                            [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to upload log, responseString: %@, file path: %@", responseString, reportPath.description]];
                        }
                        
                        [tasksCounters removeLastObject];
                        if (tasksCounters.count == 0) {
                            completion(sentReports);
                        }
                    }];
                }];

                [tasksCounters addObject: @1];
                [uploadTasks addObject: task];
            } else {
                [sentReports addObject: reportPath];
            }
        }

        if (!appKey) {
            completion(sentReports);
        }

        for (NSURLSessionDataTask *uploadTask in uploadTasks) {
            [uploadTask resume];
        }
    } else {
        if (onDone) {
            onDone(0);
        }
    }
}

- (void) uploadErrors:(FilesUploadCompletion) onDone {
    NSString *appKey = [CrashOpsController shared].appKey;
    if (!(appKey && [appKey isKindOfClass: [NSString class]] && [appKey length] > 0 && [appKey length] < 100)) {
        appKey = nil;

        if (onDone) {
            onDone(0);
        }

        return;
    }

    NSString *reportsPath = [self errorsFolderPath];

    if ([[NSFileManager defaultManager] fileExistsAtPath: reportsPath]) {
        NSArray *filesList = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString: reportsPath] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];

        if (filesList.count == 0) {
            if (onDone) {
                onDone(0);
            }

            return;
        }
        
        NSMutableDictionary *allReports = [NSMutableDictionary new];

        for (NSURL *logFileUrlPath in filesList) {
            DebugLogArgs(@"%@", logFileUrlPath);

            NSString *logFileJson = [[NSString alloc] initWithData: [NSData dataWithContentsOfURL: logFileUrlPath] encoding: NSUTF8StringEncoding];
            NSDictionary *jsonDictionary = [CrashOpsController toJsonDictionary: logFileJson];
            if ([jsonDictionary count]) {
                [allReports co_setOptionalObject: jsonDictionary forKey: logFileUrlPath];
            }
        }

        NSMutableArray *uploadTasks = [NSMutableArray new];
        NSMutableArray *tasksCounters = [NSMutableArray new];
        // An old fashion, simplified, promise.all(..) / Future.all(..) / "synchronizer" :)
        LogsUploadCompletion completion = ^void(NSArray* reportPaths) {
            if ([reportPaths count] > 0) {
                if (![CrashOps shared].isEnabled) {
                    if (onDone) {
                        onDone(0);
                    }

                    return;
                }

                NSMutableArray* reportDictionaries = [NSMutableArray new];
                for (NSURL *reportPath in allReports) {
                    NSDictionary *jsonDictionary = allReports[reportPath];

                    [reportDictionaries addObject: jsonDictionary];
                    NSError *error;
                    [[NSFileManager defaultManager] removeItemAtURL: reportPath error: &error];
                    if (error) {
                        [[CrashOpsController shared] reportInternalError: [NSString stringWithFormat:@"Failed to delete report file, error: %@", error]];
                    }
                }

                // No need:
//                            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
//                                [CrashOps shared].previousCrashReports(reportDictionaries);
//                            }];
            } else if ([reportPaths count] > 0) {
                // Considering to wait for the first VC to appear (https://spin.atomicobject.com/2014/12/30/method-swizzling-objective-c/).

                DebugLog(@"Waiting to the host app's handler to be set...");
//                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                            [[CrashOpsController shared] uploadLogs]; // Bad solution, we won't use this solution for example...
//                        });
            }
            
            if (onDone) {
                onDone(reportPaths.count);
            }
        };

        if (![allReports count]) {
            completion(@[]);

            return;
        }

        NSMutableArray *sentReports = [NSMutableArray new];

        for (NSURL *reportPath in allReports) {
            NSDictionary *jsonDictionary = allReports[reportPath];
            if (appKey) {
                NSString *fileName = [[[reportPath lastPathComponent] componentsSeparatedByString:@"."] firstObject];
                if (!fileName || ![fileName length]) {
                    [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to extract file name, file path: %@", reportPath.description]];
                    continue;
                }

                NSMutableURLRequest *request = [CrashOpsController prepareRequestWithBody: jsonDictionary forEndpoint: @"reports"];

                if (!request) {
                    [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to make request for file upload, file path: %@", reportPath]];
                    continue;
                }

                [request addValue: appKey forHTTPHeaderField:@"crashops-application-key"];

                NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request completionHandler:^(NSData * _Nullable returnedData, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    NSString *responseString = [[NSString alloc] initWithData: returnedData encoding: NSUTF8StringEncoding];
                    DebugLogArgs(@"%@", responseString);

                    BOOL wasRequestSuccessful = false;
                    NSInteger responseStatusCode = 100;
                    if (response && [response isKindOfClass: [NSHTTPURLResponse class]]) {
                        responseStatusCode = ((NSHTTPURLResponse *)response).statusCode;
                        wasRequestSuccessful = responseStatusCode >= 200 && responseStatusCode < 300;
                    }

                    [[self coGlobalOperationQueue] addOperationWithBlock:^{
                        if (wasRequestSuccessful) {
                            if (responseStatusCode == 202) {
                                DebugLogArgs(@"Accepted log and saved, file: %@", reportPath);
                                [sentReports addObject: reportPath];
                            }
                        } else {
                            if (responseStatusCode >= 400 && responseStatusCode < 500) {
                                // Integratoin error occured - deleting log anyway to avoid a large "history" folder size.
                                [sentReports addObject: reportPath];
                                
                                if (responseStatusCode == 409) {
                                    DebugLogArgs(@"This log that already sent in the past, file: %@", reportPath);
                                } else {
                                    DebugLogArgs(@"Some client error occurred for file: %@", reportPath);
                                }
                            }
                            
                            [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to upload log, responseString: %@, file path: %@", responseString, reportPath.description]];
                        }
                        
                        [tasksCounters removeLastObject];
                        if (tasksCounters.count == 0) {
                            completion(sentReports);
                        }
                    }];
                }];

                [tasksCounters addObject: @1];
                [uploadTasks addObject: task];
            } else {
                [sentReports addObject: reportPath];
            }
        }
        
        if (!appKey) {
            completion(@[]);
        }

        for (NSURLSessionDataTask *uploadTask in uploadTasks) {
            [uploadTask resume];
        }
    } else {
        if (onDone) {
            onDone(0);
        }
    }
}

- (NSMutableDictionary *) prepareCrashLogsToUpload: (NSArray *) fileUrlsList {
    NSMutableDictionary *allReports = [NSMutableDictionary new];

    for (NSURL *logFileUrlPath in fileUrlsList) {
        DebugLogArgs(@"%@", logFileUrlPath);

        NSString *logFileJson = [[NSString alloc] initWithData: [NSData dataWithContentsOfURL: logFileUrlPath] encoding: NSUTF8StringEncoding];
        
        if (![logFileJson length]) {
            [CrashOpsController logInternalError: [NSString stringWithFormat:@"Looks like this file was gone / has no content! (%@)", logFileUrlPath]];
            continue;
        }

        NSDictionary *kzCrashDictionary = [CrashOpsController toJsonDictionary: logFileJson];
        NSMutableDictionary *crashOpsDictionary = [CrashOpsController addCrashOpsConstantFields: kzCrashDictionary];

        BOOL didAdd = [allReports co_setOptionalObject: crashOpsDictionary forKey: logFileUrlPath];
        if (!didAdd) {
            [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to add CrashOps fields! (%@)", logFileUrlPath]];
        }
    }
    
    return allReports;
}

/** Uploads pending log files.
 *  Each upload bulk operation will occur one at a time.
 */
- (void) uploadLogs {
    [[self coGlobalOperationQueue] addOperationWithBlock:^{
        if (![CrashOps shared].isEnabled) return;
        if (self.crashMonitorAPI == nil) return;
        if (!self.appKey) return;
        
        if (self.isUploading) return;
        self.isUploading = true;
        
        FilesUploadCompletion completion = ^void(NSInteger filesCount) {
            NSArray *currentCrashLogFilesList = [[CrashOpsController shared] crashLogFilesList];
            NSArray *currentErrorLogFilesList = [[CrashOpsController shared] errorLogFilesList];
            
            if ([[CrashOpsController shared] errorLogFilesList].count > 0 || [[CrashOpsController shared] crashLogFilesList].count > 0) {
                BOOL isSameCrashLogsList = NO;
                BOOL isSameErrorLogsList = NO;
                if ([CrashOpsController shared].previousCrashLogFilesList) {
                    isSameCrashLogsList = currentCrashLogFilesList.count == [CrashOpsController shared].previousCrashLogFilesList.count;
                    if (isSameCrashLogsList) {
                        for (int logIndex = 0; logIndex < [CrashOpsController shared].previousCrashLogFilesList.count; ++logIndex) {
                            NSURL *previousLogFileUrlPath = [CrashOpsController shared].previousCrashLogFilesList[logIndex];
                            NSURL *currentLogFileUrlPath = currentCrashLogFilesList[logIndex];
                            // Meaning - it's the exact same list!
                            isSameCrashLogsList &= [[previousLogFileUrlPath lastPathComponent] isEqualToString: [currentLogFileUrlPath lastPathComponent]];
                        }
                    }
                }
                
                if ([CrashOpsController shared].previousErrorLogFilesList) {
                    isSameErrorLogsList = currentErrorLogFilesList.count == [CrashOpsController shared].previousErrorLogFilesList.count;
                    if (isSameErrorLogsList) {
                        for (int logIndex = 0; logIndex < [CrashOpsController shared].previousErrorLogFilesList.count; ++logIndex) {
                            NSURL *previousLogFileUrlPath = [CrashOpsController shared].previousErrorLogFilesList[logIndex];
                            NSURL *currentLogFileUrlPath = currentErrorLogFilesList[logIndex];
                            // We're OK if the indicator will point out that the crashes are the same!
                            isSameErrorLogsList &= [[previousLogFileUrlPath lastPathComponent] isEqualToString: [currentLogFileUrlPath lastPathComponent]];
                        }
                    }
                }
                
                [CrashOpsController shared].isUploading = false;
                
                [CrashOpsController shared].previousCrashLogFilesList = currentCrashLogFilesList;
                [CrashOpsController shared].previousErrorLogFilesList = currentErrorLogFilesList;
                
                if (isSameCrashLogsList && isSameErrorLogsList) {
                    // Preventing endless loops
                    [CrashOpsController logInternalError:@"Failing to upload the same files... aborting!"];
                } else {
                    // Retry and see if there are leftovers...
                    [[CrashOpsController shared] uploadLogs];
                }
            } else {
                [[CrashOpsController shared] cleanAllTraces];
                [CrashOpsController shared].isUploading = false;
            }
        };
        
        
        NSMutableArray *uploadResults = [NSMutableArray new];
        
        [self uploadCrashes: ^(NSInteger filesCount) {
            [uploadResults addObject: [NSNumber numberWithLong: filesCount]];
            if (uploadResults.count == 2) {
                NSInteger total = ((NSNumber*)[uploadResults objectAtIndex: 0]).integerValue + ((NSNumber*)[uploadResults objectAtIndex: 1]).integerValue;
                completion(total);
            }
        }];
        
        [self uploadErrors: ^(NSInteger filesCount) {
            [uploadResults addObject:[NSNumber numberWithLong:filesCount]];
            if (uploadResults.count == 2) {
                NSInteger total = ((NSNumber*)[uploadResults objectAtIndex: 0]).integerValue + ((NSNumber*)[uploadResults objectAtIndex: 1]).integerValue;
                completion(total);
            }
        }];
    }];
}

+ (NSMutableDictionary *) addCrashOpsConstantFields:(NSDictionary *) reportJson {
    if (![reportJson count]) {
        return [reportJson mutableCopy];
    }

    NSMutableDictionary *reportCopy = [reportJson mutableCopy];
    reportCopy[@"devicePlatform"] = @"ios";
    reportCopy[@"crashOpsSdkVersion"] = [CrashOps sdkVersion]; //[NSString stringWithCString:CrashOpsVersionString encoding: NSUTF8StringEncoding];
    reportCopy[@"buildMode"] = [CrashOps isRunningOnDebugMode] ? @"DEBUG" : @"RELEASE";

    return reportCopy;
}

+ (NSMutableURLRequest *) prepareRequestWithBody:(NSDictionary *) bodyDictionary forEndpoint: (NSString *) apiEndpoint {
    NSData *postBody = [CrashOpsController toJsonData: bodyDictionary];
    if (![postBody length]) {
        return nil;
    }

    NSString *serverUrlString = [NSString stringWithFormat: @"https://crashops.com/api/%@", apiEndpoint];
    //NSString *serverUrlString = [NSString stringWithFormat: @"https://unity1.zcps.co/crashops/%@", apiEndpoint];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: serverUrlString]];

    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request setHTTPShouldHandleCookies:NO];
    [request setTimeoutInterval:60];
    [request setHTTPMethod:@"POST"];
    [request setValue: @"gzip" forHTTPHeaderField: @"Accept-Encoding"];

    NSString *contentType = [NSString stringWithFormat:@"application/json; charset=utf-8"];
    [request setValue: contentType forHTTPHeaderField:@"Content-Type"];

    [request setHTTPBody: postBody];

    return request;
}

- (void) configureAdvancedSettings {
    KSCrash* handler = [KSCrash sharedInstance];

    NSDictionary *metadata;
    if ([CrashOps shared].metadata && [[CrashOps shared].metadata count]) {
        metadata = [[CrashOps shared].metadata copy];
    } else {
        metadata = [NSDictionary new];
    }

    handler.userInfo = @{@"hostAppInfo": metadata,
                         @"deviceInfo": [CrashOpsController getDeviceInfo],
                         @"sessionId": self.appSessionId};

    if ([CrashOps shared].excludeClassesDetails) {
        // Do not introspect these classes
        handler.doNotIntrospectClasses = [[CrashOps shared].excludeClassesDetails copy];
    }
    
    [KSCrash sharedInstance].onEventSaved = ^(NSString *eventId){
        [[CrashOpsController shared] onEventFileCreated: eventId];
    };
}

// Saves extra info for this new incident
-(void) onEventFileCreated:(NSString *) eventId {
    //   the `eventId` will be located under "report"->"id"
    NSLog(@"New event ID saved: %@", eventId);

    NSString *eventIdFile = [[self eventsFolderPath] stringByAppendingPathComponent: eventId];

    NSData *eventIdData = [appSessionId dataUsingEncoding: NSUTF8StringEncoding];
    [eventIdData writeToFile: eventIdFile options: NSDataWritingAtomic error: nil];
    
    NSString *sessionIdFile = [[self sessionsFolderPath] stringByAppendingPathComponent: appSessionId];
    
    NSData *sessionIdData = [eventId dataUsingEncoding: NSUTF8StringEncoding];
    [sessionIdData writeToFile: sessionIdFile options: NSDataWritingAtomic error: nil];
}

-(void) handleException:(NSException *) exception {
    [self passToOtherExceptionHadlers: exception];

    if ([CrashOps shared].isEnabled) {
        // Crash occurred, already handled by KZCrash.
    }

    if ([CrashOps shared].appExceptionHandler) {
        [CrashOps shared].appExceptionHandler(exception);
    }
}

/**
 Passing the exception to other exception handlers in the app.
 It's on purpose on a dedicated method so it will appear in the log, that CrashOps just passed it to others.
*/
-(void) passToOtherExceptionHadlers:(NSException *) exception {
    if (co_oldHandler) {
        co_oldHandler(exception);
    }
}

/**
 Logs immediately a non-fatal error details with built-in screen traces details into a file.
 Then CrashOps attempts to upload with no farther wating.
 */
- (BOOL) logError:(NSDictionary *) errorDetails {
    if (!errorDetails) return NO;
    if (![errorDetails count]) return NO;
    
    NSDate *now = [NSDate date];
    NSTimeInterval timeMilliseconds = [now timeIntervalSince1970] * 1000;
    NSInteger timestamp = ((NSInteger) timeMilliseconds);
    
    NSString *sessionId = appSessionId;
    [[self coGlobalOperationQueue] addOperationWithBlock:^{
        NSString *nowString = [CrashOpsController stringFromDate: now withFormat: @"yyyy-MM-dd-HH-mm-ss-SSS_ZZZ"];
        
        NSString *filePath = [[self errorsFolderPath] stringByAppendingPathComponent: [NSString stringWithFormat:@"ios_error_%@_%@.log", nowString, [[NSUUID UUID] UUIDString]]];
        
        NSArray *breadcrumbs = [ScreenTracer tracesReportForSessionId: sessionId];
        
        NSDictionary *jsonDictionary = @{@"errorDetails": errorDetails,
                                         @"report":@{@"id": [NSNumber numberWithInteger: timestamp],
                                                     @"time": nowString},
                                         //@"details": [self generateReport: [NSException exceptionWithName:@"Error" reason:@"" userInfo:@{@"isFatal": NO}]],
                                         @"details": [self generateReport: nil],
                                         @"screenTraces": breadcrumbs,
                                         @"isFatal": @NO
        };
        
        NSData *errorData = [CrashOpsController toJsonData: jsonDictionary];
        
        NSError *error;
        BOOL didSave = [errorData writeToFile: filePath options: NSDataWritingAtomic error: &error];
        if (!didSave || error) {
            DebugLogArgs(@"Failed to save log with error %@", error);
        } else {
            DebugLog(@"Log saved.");
        }
        
        if (didSave) {
            [self uploadLogs];
        }
    }];

    return true;
}

-(NSString *) crashesFolderPath {
    NSString *basePath = [KSCrash sharedInstance].basePath;
    if (!basePath) return @"";

    NSString *reportsPath = [basePath stringByAppendingPathComponent: @"Reports"];
    return reportsPath;
}

-(NSString *) errorsFolderPath {
    if (errorsPath != nil) {
        return errorsPath;
    }

    NSString *path = [self.crashOpsLibraryPath stringByAppendingPathComponent: @"Errors"];

    BOOL isDir = YES;
    BOOL isCreated = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Failed to create folder %@", path);
        } else {
            isCreated = YES;
        }
    } else {
        isCreated = YES;
    }

    if (isCreated) {
        errorsPath = path;
    }

    return errorsPath;
}

/**
 *  Session IDs folder path.
*/
-(NSString *) sessionsFolderPath {
    if (sessionsPath != nil) {
        return sessionsPath;
    }

    NSString *path = [self.crashOpsLibraryPath stringByAppendingPathComponent: @"Sessions"];

    BOOL isDir = YES;
    BOOL isCreated = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Failed to create folder %@", path);
        } else {
            isCreated = YES;
        }
    } else {
        isCreated = YES;
    }

    if (isCreated) {
        sessionsPath = path;
    }

    return sessionsPath;
}
/**
 *  Event IDs folder path.
*/
-(NSString *) eventsFolderPath {
    if (eventsPath != nil) {
        return eventsPath;
    }

    NSString *path = [self.crashOpsLibraryPath stringByAppendingPathComponent: @"Events"];

    BOOL isDir = YES;
    BOOL isCreated = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Failed to create folder %@", path);
        } else {
            isCreated = YES;
        }
    } else {
        isCreated = YES;
    }

    if (isCreated) {
        eventsPath = path;
    }

    return eventsPath;
}

/**
*  All screen trace logs folder path.
*/
-(NSString *) tracesFolderPath {
    if (tracesPath != nil) {
        return tracesPath;
    }

    NSString *path = [self.crashOpsLibraryPath stringByAppendingPathComponent: @"Traces"];

    BOOL isDir = YES;
    BOOL isCreated = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Failed to create folder %@", path);
        } else {
            isCreated = YES;
        }
    } else {
        isCreated = YES;
    }

    if (isCreated) {
        tracesPath = path;
    }

    return tracesPath;
}

/**
*  Current session's screen trace logs folder path.
*/
-(NSString *) currentSessionTracesFolderPath {
//    if (currentTracesPath != nil) {
//        return currentTracesPath;
//    }

    NSString *path = [[self tracesFolderPath] stringByAppendingPathComponent: appSessionId];

    BOOL isDir = YES;
    BOOL isCreated = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Failed to create folder %@", path);
        } else {
            isCreated = YES;
        }
    } else {
        isCreated = YES;
    }

    if (isCreated) {
        currentTracesPath = path;
    }

    return currentTracesPath;
}

-(NSString *) crashOpsLibraryPath {
    if (libraryPath != nil) {
        return libraryPath;
    }

    NSString *path = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent: @"CrashOps"];

    BOOL isDir = YES;
    BOOL isCreated = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Failed to create folder %@", path);
        } else {
            isCreated = YES;
        }
    } else {
        isCreated = YES;
    }

    if (isCreated) {
        libraryPath = path;
    }

    return libraryPath;
}

-(NSMutableDictionary *) generateReport:(NSException *) exception {
    NSMutableDictionary *jsonReport = [NSMutableDictionary new];

    NSThread *current = [NSThread currentThread];
    [jsonReport co_setOptionalObject: [current description] forKey: @"currentThread"];
    [jsonReport co_setOptionalObject: self.appSessionId forKey: @"sessionId"];

    NSMutableArray *stackTrace;

    if (exception) {
        stackTrace = [exception.callStackSymbols mutableCopy];
        [jsonReport co_setOptionalObject: exception.reason forKey: @"reason"];
        if (exception.userInfo) {
            [jsonReport co_setOptionalObject: exception.userInfo forKey: @"moreInfo"];
        }
    } else {
        stackTrace = [[NSThread callStackSymbols] mutableCopy];
        [stackTrace removeObjectAtIndex: 0];
    }

    [jsonReport co_setOptionalObject: stackTrace forKey: @"stackTrace"];

    [jsonReport co_setOptionalObject: CrashOps.shared.metadata forKey: @"metadata"];
    
//    [jsonReport setObject: [NSBundle allFrameworks] forKey: @"allFrameworks"];

    return jsonReport;
}

- (ScreenTracer *)screenTracer {
    return _screenTracer;
}

+(NSString *) ipsFilesLibraryPath {
    CrashOpsController *instance = [CrashOpsController shared];
    if (instance.ipsFilesPath != nil) {
        return instance.ipsFilesPath;
    }

    NSString *path = [[CrashOpsController shared].crashOpsLibraryPath stringByAppendingPathComponent: @"ipsFiles"];

    BOOL isDir = YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Failed to create folder %@", path);
        }
    }

    instance.ipsFilesPath = path;

    return instance.ipsFilesPath;
}

static void ourExceptionHandler(NSException *exception) {
    [[CrashOpsController shared] handleException: exception];
}

- (void) flushToDisk:(ScreenDetails *) screenDetails {
    [[self coGlobalOperationQueue] addOperationWithBlock:^{
        NSUInteger timestamp = screenDetails.timestamp;
        NSString *filePath = [[[CrashOpsController shared] currentSessionTracesFolderPath] stringByAppendingPathComponent: [NSString stringWithFormat:@"%lu.log", (unsigned long) timestamp]];

        NSData *traceData = [[CrashOpsController toJsonString: [screenDetails toDictionary]] dataUsingEncoding: NSUTF8StringEncoding];

        BOOL didSave = [traceData writeToFile: filePath options: NSDataWritingAtomic error: nil];
        if (!didSave) {
            [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to flush screen details to disk. Screen details: %@", screenDetails]];
        }
    }];
}

-(BOOL) cleanUpEventId:(NSString *) eventId andReportPath:(NSURL *) reportPath {
    NSString *screenTracesFolderPath = [CrashOpsController screenTracesFolderFromEventId: eventId];

    NSError *error;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL didRemove = [fileManager removeItemAtURL: reportPath error: &error];
    if (!didRemove || error) {
        [[CrashOpsController shared] reportInternalError: [NSString stringWithFormat:@"Failed to delete report file, error: %@", error]];
    }

    if (screenTracesFolderPath) {
        didRemove &= [fileManager removeItemAtPath: screenTracesFolderPath error: &error];
    }
    
    NSString *sessionId = [CrashOpsController sessionIdFromEventId: eventId];
    NSString *sessionIdPath = [[[CrashOpsController shared] sessionsFolderPath] stringByAppendingPathComponent: sessionId];

    NSString *eventIdPath = [[[CrashOpsController shared] eventsFolderPath] stringByAppendingPathComponent: eventId];
    didRemove &= [fileManager removeItemAtPath: eventIdPath error: &error];
    didRemove &= [fileManager removeItemAtPath: sessionIdPath error: &error];

    if (!didRemove || error) {
        [[CrashOpsController shared] reportInternalError: [NSString stringWithFormat:@"Failed to delete screen traces file file, error: %@", error]];
    }

    return didRemove;
}

-(BOOL) cleanAllTraces {
    NSString *screenTracesFolderPath = [[CrashOpsController shared] tracesFolderPath];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    BOOL didRemoveAll = YES;
    if ([[NSFileManager defaultManager] fileExistsAtPath: screenTracesFolderPath]) {
        NSArray *filesList = [fileManager contentsOfDirectoryAtURL:[NSURL URLWithString: screenTracesFolderPath] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];
        for (NSURL *fileUrl in filesList) {
            // guard
            if ([[fileUrl lastPathComponent] isEqualToString: appSessionId]) { continue; }

            [fileManager removeItemAtURL: fileUrl error: &error];
            didRemoveAll &= error == nil;
        }
    }

    if (!didRemoveAll || error) {
        [[CrashOpsController shared] reportInternalError: [NSString stringWithFormat:@"Failed to delete report file, error: %@", error]];
    }
    
    return didRemoveAll;
}

+(NSString *) screenTracesFolderFromEventId:(NSString *) eventId {
    NSString *sessionId = [CrashOpsController sessionIdFromEventId: eventId];

    return [CrashOpsController screenTracesFolderFromSessionId: sessionId];
}

+(NSString *) screenTracesFolderFromSessionId:(NSString *) sessionId {
    NSString *sessionTracesFolderPath;

    if (sessionId) {
        NSString *tracesFolderPath = [[CrashOpsController shared] tracesFolderPath];
        sessionTracesFolderPath = [tracesFolderPath stringByAppendingPathComponent: sessionId];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath: sessionTracesFolderPath]) {
            sessionTracesFolderPath = nil;
        }
    }

    return sessionTracesFolderPath;
}

+(NSString *) sessionIdFromEventId:(NSString *) eventId {
    NSString *sessionIdFilePath = [[[CrashOpsController shared] eventsFolderPath] stringByAppendingPathComponent: eventId];

    NSString *sessionId;
    if ([[NSFileManager defaultManager] fileExistsAtPath: sessionIdFilePath]) {
        NSData *sessionIdData = [NSData dataWithContentsOfFile: sessionIdFilePath];

        if (sessionIdData) {
            sessionId = [[NSString alloc] initWithData: sessionIdData encoding:NSUTF8StringEncoding];
            DebugLogArgs(@"eventId -> sessionId: %@", sessionId);
        }
    }

    return sessionId;
}

+(NSString *) eventIdFromSessionId:(NSString *) sessionId {
    NSString *eventIdFile = [[[CrashOpsController shared] eventsFolderPath] stringByAppendingPathComponent: sessionId];

    NSString *eventId;
    if ([[NSFileManager defaultManager] fileExistsAtPath: eventIdFile]) {
            NSData *eventIdData = [NSData dataWithContentsOfFile: eventIdFile];

        if (eventIdData) {
            eventId = [[NSString alloc] initWithData: eventIdData encoding:NSUTF8StringEncoding];
            DebugLogArgs(@"sessionId -> eventId: %@", eventId);
        }
    }

    return eventId;
}

+(NSString *) toJsonString:(NSDictionary *) jsonDictionary {
    NSError *error;
    NSData *jsonData = [CrashOpsController toJsonData: jsonDictionary];

    if (![jsonData length]) {
        return nil;
    }

    NSString* jsonString = [[NSString alloc] initWithData: jsonData encoding: NSUTF8StringEncoding];
    DebugLogArgs(@"jsonString: %@", jsonString);
    
    return error ? nil : jsonString;
}

+(NSData *) toJsonData:(NSDictionary *) jsonDictionary {
    if (![jsonDictionary isKindOfClass: [NSDictionary class]] || ![jsonDictionary count]) {
        // Avoiding 'NSInvalidArgumentException'
        return nil;
    }

    NSData *jsonData;
    NSError *error;

    @try {
        // Instead of NSJSONWritingPrettyPrinted, we're not using any option.
        jsonData = [NSJSONSerialization dataWithJSONObject: jsonDictionary options: kNilOptions error: &error];
    } @catch (NSException *exception) {
        error = [NSError errorWithDomain: kSdkName code: 1 userInfo: @{@"exception":exception}];
    } @finally {
        // ignore
    }

    if (error) {
        [CrashOpsController logLibraryError: error];
    }

    return jsonData;
}

+(NSDictionary *) toJsonDictionary:(NSString *) jsonString {
    if (![jsonString length]) {
        [CrashOpsController logInternalError: @"Missing JSON string"];
        return @{};
    }

    NSError *jsonError;
    NSData *objectData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];

    if (!objectData) {
        [CrashOpsController logInternalError: @"Failed to create JSON data"];
        return @{};
    }

    NSDictionary *jsonDictionary;
    @try {
        // Instead of NSJSONWritingPrettyPrinted, we're not using any option.
        jsonDictionary = [NSJSONSerialization JSONObjectWithData: objectData
        options: NSJSONReadingMutableContainers
          error: &jsonError];
    } @catch (NSException *exception) {
        jsonError = [NSError errorWithDomain:kSdkName code: 1 userInfo: @{@"exception":exception}];
    } @finally {
        // ignore
    }

    if (jsonError) {
        [CrashOpsController logLibraryError: jsonError];
    }

    return jsonDictionary;
}

NSUncaughtExceptionHandler *exceptionHandlerPtr = &ourExceptionHandler;

+(void) initialize {
    DebugLog(@"App is loading...");
    g_dateFormatter = [[NSDateFormatter alloc] init];
    [g_dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
}

+ (void) load {
    [[CrashOpsController shared] onAppIsLoading];
    DebugLog(@"CrashOps library is being loaded");
}

+ (NSDictionary *) getDeviceInfo {
    UIDevice* device = [UIDevice currentDevice];
    struct utsname un;
    uname(&un);

    CGRect screenSize = [[UIScreen mainScreen] bounds];
    
    NSMutableDictionary *info = [@{
      @"name" : [device name],
      @"screenSize": [NSString stringWithFormat:@"%ldx%ld", (long)((NSInteger)screenSize.size.width), (long)((NSInteger)screenSize.size.height)],
      @"systemName" : [device systemName],
      @"systemVersion" : [device systemVersion],
      @"model" : [device model],
      @"localizedModel" : [device localizedModel],
      @"isPhysicalDevice" : CrashOpsController.isRunningOnSimulator ? @"false" : @"true",
      @"utsname" : @{
        @"sysname" : @(un.sysname),
        @"nodename" : @(un.nodename),
        @"release" : @(un.release),
        @"version" : @(un.version),
        @"machine" : @(un.machine),
      }
    } mutableCopy];

    // Setting nullable values
    [info co_setOptionalObject: [CrashOpsController deviceId] forKey: @"identifierForVendor"];

    return [info copy];
}

// Get the system version from Firebase Core's App Environment Util
+ (NSString *) iosVersion {
#if TARGET_OS_IOS || TARGET_OS_TV
  return [UIDevice currentDevice].systemVersion;
#elif TARGET_OS_OSX || TARGET_OS_WATCH
  return [NSProcessInfo processInfo].operatingSystemVersionString;
#endif
}

+ (NSString *) deviceId {
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
}

+ (NSData*) gzippedWithCompressionLevel:(NSData*) original {
    if(!original) {
        return [NSData data];
    }

    uInt length = (uInt)[original length];
    if(length == 0) {
        return [NSData data];
    }

    z_stream stream = {0};
    stream.next_in = (Bytef*)[original bytes];
    stream.avail_in = length;

    int err;

    err = deflateInit2(&stream,
                       -1,
                       Z_DEFLATED,
                       (16+MAX_WBITS),
                       9,
                       Z_DEFAULT_STRATEGY);
    if(err != Z_OK) {
        return nil;
    }

    NSMutableData* compressedData = [NSMutableData dataWithLength:(NSUInteger)(length * 1.02 + 50)];
    Bytef* compressedBytes = [compressedData mutableBytes];
    NSUInteger compressedLength = [compressedData length];

    while(err == Z_OK) {
        stream.next_out = compressedBytes + stream.total_out;
        stream.avail_out = (uInt)(compressedLength - stream.total_out);
        err = deflate(&stream, Z_FINISH);
    }

    if(err != Z_STREAM_END) {
        deflateEnd(&stream);
        return nil;
    }

    [compressedData setLength:stream.total_out];

    deflateEnd(&stream);

    return compressedData;
}

+ (NSString*) stringFromDate:(NSDate*) date withFormat:(NSString *) format {
    if(![date isKindOfClass:[NSDate class]]) {
        return nil;
    }

    if (format) {
        [g_dateFormatter setDateFormat: format];
    } else {
        [g_dateFormatter setDateFormat: @"yyyy-MM-dd-HH-mm-ss-SSS_ZZZ"];
    }

    return [g_dateFormatter stringFromDate:date];
}

@end

@implementation NSMutableDictionary (CO_NilSafeDictionary)

- (BOOL)co_setOptionalObject:(id)anObject forKey:(id<NSCopying>)aKey {
    BOOL didAdd = NO;
    if (!anObject) {
        [CrashOpsController logInternalError: @"Prevented from adding a `nil` object!"];
        return didAdd;
    }

    if (aKey) {
        [self setObject: anObject forKey: aKey];
        didAdd = YES;
    } else {
        [CrashOpsController logInternalError: @"Prevented from adding an object for a `nil` key!"];
    }
    
    return didAdd;
}

@end
