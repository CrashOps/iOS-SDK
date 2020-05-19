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
#import <AdSupport/ASIdentifierManager.h>
#import <zlib.h>

#import "ScreenTracer.h"
#import "ScreenDetails.h"

typedef void(^FilesUploadCompletion)(NSInteger filesCount);

typedef void(^LogsUploadCompletion)(NSArray *reports);

@interface CrashOpsController()

@property (nonatomic, strong) NSUserDefaults *coUserDefaults;
@property (nonatomic, strong) NSString *libraryPath;
@property (nonatomic, strong) NSString *errorsPath;
@property (nonatomic, strong) NSString *tracesPath;
@property (nonatomic, strong) NSString *ipsFilesPath;
@property (nonatomic, strong) NSObject *appFinishedLaunchObserver;
@property (nonatomic, strong) NSNumber *isEnabled_Optional;

@property (nonatomic, strong) NSArray *previousErrorLogFilesList;
@property (nonatomic, strong) NSArray *previousCrashLogFilesList;

@property (nonatomic) NSOperationQueue* coGlobalOperationQueue;
@property (nonatomic, assign) KSCrashMonitorAPI* crashMonitorAPI;
@property (nonatomic, assign) BOOL didAppFinishLaunching;
@property (nonatomic, assign) BOOL isUploading;
@property (nonatomic, assign) BOOL isDebugModeEnabled;

@property (nonatomic, strong) ScreenTracer *screenTracer;

+(void) logInternalError:(NSString *) internalError;

@end

#define DebugLog(msg) if (CrashOpsController.isDebugModeEnabled) { NSLog(msg); }
#define DebugLogArgs(msg, args) if (CrashOpsController.isDebugModeEnabled) { NSLog(msg, args); }

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

@synthesize libraryPath;
@synthesize errorsPath;
@synthesize tracesPath;
@synthesize appFinishedLaunchObserver;
@synthesize coGlobalOperationQueue;
@synthesize isEnabled;
@synthesize isEnabled_Optional;
@synthesize didAppFinishLaunching;
@synthesize isUploading;
@synthesize crashMonitorAPI;
@synthesize appKey;
@synthesize coUserDefaults;
//@synthesize screenTracer;
@synthesize isDebugModeEnabled;

NSUncaughtExceptionHandler *co_oldHandler;

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
        coGlobalOperationQueue.name = kSdkIdentifier;
        isUploading = NO;
        isDebugModeEnabled = NO;
        isEnabled = YES;
        coUserDefaults = [[NSUserDefaults alloc] initWithSuiteName: kSdkIdentifier];
        _screenTracer = [ScreenTracer new];
    }

    return self;
}

/**
 Using conditional compilation flags: https://miqu.me/blog/2016/07/31/xcode-8-new-build-settings-and-analyzer-improvements/
 */

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
    if(error == nil) {
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

+ (BOOL)isDebugModeEnabled {
    return _shared.isDebugModeEnabled;
}

- (void)onChangedHandler {
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

- (void) setIsEnabled:(BOOL)isOn {
    if (isEnabled_Optional != nil && isEnabled == isOn) return;

    isEnabled = isOn;
    isEnabled_Optional = [NSNumber numberWithBool: isOn];

    if (isOn) {
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

// TODO: Report to some dedicated analytics tool
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

-(void) setupFromInfoPlist {
    NSString *infoPlistPath = [[NSBundle mainBundle] pathForResource:@"CrashOpsConfig-info" ofType:@"plist"];
    NSDictionary* infoPlist = [NSDictionary dictionaryWithContentsOfFile: infoPlistPath];

    NSString* appKey = infoPlist[@"APPLICATION_KEY"];
    if (appKey == nil) {
        appKey = @"";
    }

    NSString* isDisabledOnRelease = infoPlist[@"IS_DISABLED_ON_RELEASE"];
    if (isDisabledOnRelease == nil) {
        isDisabledOnRelease = @"0";
    }
    BOOL config_isDisabledOnRelease = isDisabledOnRelease.boolValue;

    NSString* isTracingScreens = infoPlist[@"IS_TRACING_SCREENS"];
    if (isTracingScreens == nil) {
        isTracingScreens = @"1";
    }
    BOOL config_isTracingScreens = isTracingScreens.boolValue;

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
    if (isEnabledString == nil) {
        isEnabledString = @"1";
    }
    BOOL config_isEnabled = isEnabledString.boolValue;

    BOOL isEnabled = config_isEnabled;
    
    if (CrashOps.isRunningOnDebugMode && config_isDisabledOnDebug) {
        isEnabled = NO;
    }

    if (!CrashOps.isRunningOnDebugMode && config_isDisabledOnRelease) {
        isEnabled = NO;
    }

    [CrashOps shared].isEnabled = isEnabled;
    [CrashOps shared].isTracingScreens = config_isTracingScreens;
    [CrashOps shared].appKey = appKey;
}

-(void)runTests {
    if (!isDebugModeEnabled) return;

    COAssert([CrashOpsController toJsonDictionary: @""].count == 0, @"empty strings should become empty dictionaries", YES);
    
    COAssert([CrashOpsController toJsonDictionary: nil].count == 0, @"nil strings should become empty dictionaries", YES);

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
}

- (NSArray *) errorLogFilesList {
    NSString *appKey = CrashOps.shared.appKey;
    if (!(appKey && [appKey length] > 0 && [appKey length] < 100)) {
        appKey = nil;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath: [self errorsLibraryPath]]) {
        NSArray *filesList = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString: [self errorsLibraryPath]] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];
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
    NSString *basePath = [KSCrash sharedInstance].basePath;
    if (!basePath) {
        if (onDone) {
            onDone(0);
        }

        return;
    }

    NSString *reportsPath = [basePath stringByAppendingPathComponent: @"Reports"];
    NSString *appKey = [CrashOpsController shared].appKey;
    if (!(appKey && [appKey length] > 0 && [appKey length] < 100)) {
        appKey = nil;
    }

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
            
            if (![logFileJson length]) {
                [CrashOpsController logInternalError: [NSString stringWithFormat:@"Looks like this file was gone / has no content! (%@)", logFileUrlPath]];
                continue;
            }

            NSDictionary *kzCrashDictionary = [CrashOpsController toJsonDictionary: logFileJson];
            NSMutableDictionary *crashOpsDictionary = [CrashOpsController addCrashOpsConstantFields: kzCrashDictionary];

            BOOL didAdd = [CrashOpsController safeDictionary: allReports addObject: crashOpsDictionary forKey: logFileUrlPath];
            if (!didAdd) {
                [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to add CrashOps fields! (%@)", logFileUrlPath]];
            }
        }

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
                        NSError *error;
                        NSString *eventId = [AppleCrashReportGenerator reportId: jsonDictionary];
                        NSString *screenTracesFilePath = [[self tracesLibraryPath] stringByAppendingPathComponent: [NSString stringWithFormat:@"screen_traces_%@.log", eventId]];

                        BOOL didRemove = [[NSFileManager defaultManager] removeItemAtURL: reportPath error: &error];
                        if (!didRemove || error) {
                            [[CrashOpsController shared] reportInternalError: [NSString stringWithFormat:@"Failed to delete report file, error: %@", error]];
                        }
                        
                        didRemove = [[NSFileManager defaultManager] removeItemAtPath: screenTracesFilePath error: &error];
                        if (!didRemove || error) {
                            if ([CrashOps shared].isTracingScreens) {
                                [[CrashOpsController shared] reportInternalError: [NSString stringWithFormat:@"Failed to delete screen traces file file, error: %@", error]];
                            }
                        }
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
//                NSString *timestamp = [CrashOpsController stringFromDate: logTime withFormat: nil];

                NSString *screenTracesFilePath = [[self tracesLibraryPath] stringByAppendingPathComponent: [NSString stringWithFormat:@"screen_traces_%@.log", eventId]];

                if ([[NSFileManager defaultManager] fileExistsAtPath: screenTracesFilePath]) {
                    NSString *logFileJson = [[NSString alloc] initWithData: [NSData dataWithContentsOfFile: screenTracesFilePath] encoding: NSUTF8StringEncoding];
                    if (logFileJson && [logFileJson length]) {
                        NSDictionary *additionalInfoDictionary = [CrashOpsController toJsonDictionary: logFileJson];

                        if ([additionalInfoDictionary count]) {
                            // Merging dictionaries
                            for (NSString *key in [additionalInfoDictionary allKeys]) {
                                [CrashOpsController safeDictionary: jsonDictionary addObject: [additionalInfoDictionary objectForKey: key] forKey: key];
                            }
                        }
                    }
                }

                NSMutableURLRequest *request = [CrashOpsController prepareRequestWithJson: jsonDictionary];

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

                    if (wasRequestSuccessful) {
                        if (responseStatusCode == 202) {
                            DebugLogArgs(@"Accepted log and saved, file: %@", reportPath);
                            [sentReports addObject: reportPath];
                        }
                    } else {
                        if (responseStatusCode == 409) {
                            DebugLogArgs(@"Sent log that already saved in the past, file: %@", reportPath);
                            [sentReports addObject: reportPath];
                        }

                        [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to upload log, responseString: %@, file path: %@", responseString, reportPath.description]];
                    }

                    [tasksCounters removeLastObject];
                    if (tasksCounters.count == 0) {
                        completion(sentReports);
                    }
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
    }
}

- (void) uploadErrors:(FilesUploadCompletion) onDone {
    NSString *appKey = [CrashOpsController shared].appKey;
    if (!(appKey && [appKey length] > 0 && [appKey length] < 100)) {
        appKey = nil;

        if (onDone) {
            onDone(0);
        }

        return;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath: [self errorsLibraryPath]]) {
        NSArray *filesList = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString: [self errorsLibraryPath]] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];

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
                [CrashOpsController safeDictionary:allReports addObject: jsonDictionary forKey: logFileUrlPath];
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

                NSMutableURLRequest *request = [CrashOpsController prepareRequestWithJson: jsonDictionary];

                if (!request) {
                    [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to make request for file upload, file path: %@", reportPath]];
                    continue;
                }

                [request addValue: appKey forHTTPHeaderField:@"crashops-application-key"];

                NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request completionHandler:^(NSData * _Nullable returnedData, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    NSString *responseString = [[NSString alloc] initWithData: returnedData encoding: NSUTF8StringEncoding];
                    DebugLogArgs(@"%@", responseString);

                    BOOL wasRequestSuccessful = false;
                    if (response && [response isKindOfClass: [NSHTTPURLResponse class]]) {
                        NSInteger responseStatusCode = ((NSHTTPURLResponse *)response).statusCode;
                        wasRequestSuccessful = responseStatusCode >= 200 && responseStatusCode < 300;
                    }

                    if (wasRequestSuccessful) {
                        [sentReports addObject: reportPath];
                    } else {
                        [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to upload log, responseString: %@, file path: %@", responseString, reportPath.description]];
                    }

                    [tasksCounters removeLastObject];
                    if (tasksCounters.count == 0) {
                        completion(sentReports);
                    }
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
    }
}

/** Uploads pending log files.
 *  Each upload bulk operation will occur one at a time.
 */
- (void) uploadLogs {
    [[self coGlobalOperationQueue] addOperationWithBlock:^{
        if (![CrashOps shared].isEnabled) return;
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

+ (NSMutableURLRequest *) prepareRequestWithJson:(NSDictionary *) reportJson {
    NSMutableDictionary *editedJson = [NSMutableDictionary dictionaryWithDictionary: reportJson];

    NSString *serverUrlString = @"https://crashops.com/api/reports";

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: serverUrlString]];

    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request setHTTPShouldHandleCookies:NO];
    [request setTimeoutInterval:60];
    [request setHTTPMethod:@"POST"];
    [request setValue: @"gzip" forHTTPHeaderField: @"Accept-Encoding"];

    NSString *contentType = [NSString stringWithFormat:@"application/json; charset=utf-8"];
    [request setValue: contentType forHTTPHeaderField:@"Content-Type"];

    NSData *postBody = [CrashOpsController toJsonData: editedJson];
    [request setHTTPBody: postBody];

    if (![postBody length]) {
        return nil;
    }

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

    handler.userInfo = @{@"hostAppInfo": metadata, @"deviceInfo": [CrashOpsController getDeviceInfo]};
    
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

    if ([CrashOps shared].isTracingScreens) {
        [self saveCurrentScreenTracesSnapshot: eventId];
    }
}

/**
Creates a separated screen traces details file so CrashOps won't interrupt KZCrash logging operations.
Later (on next app launch) CrashOps will merge these traces with the crash event that created here.
*/
-(void) saveCurrentScreenTracesSnapshot:(NSString *) screenTracesSnapshotId {
    // Logging screen traces for with 'screenTracesSnapshotId'
    NSString *filePath = [[self tracesLibraryPath] stringByAppendingPathComponent: [NSString stringWithFormat:@"screen_traces_%@.log", screenTracesSnapshotId]];

    NSMutableArray *traces = [NSMutableArray new];
    for (ScreenDetails *details in [[CrashOpsController shared] screenTracer].breadcrumbsReport) {
        [traces addObject:[details toDictionary]];
    }

    NSData *screenTracesData = [CrashOpsController toJsonData: @{@"screenTraces": traces}];

    NSError *error;
    BOOL didSave = [screenTracesData writeToFile: filePath options: NSDataWritingAtomic error: &error];
    if (!didSave || error) {
        DebugLogArgs(@"Failed to save log with error %@", error);
    } else {
        DebugLog(@"Log saved.");
    }
}

-(void) handleException:(NSException *) exception {
    if (co_oldHandler) {
        co_oldHandler(exception);
    }

    if ([CrashOps shared].isEnabled) {
        // Crash occurred, already handled by KZCrash.
    }

    if ([CrashOps shared].appExceptionHandler) {
        [CrashOps shared].appExceptionHandler(exception);
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

    NSString *nowString = [CrashOpsController stringFromDate: now withFormat: @"yyyy-MM-dd-HH-mm-ss-SSS_ZZZ"];

    NSString *filePath = [[self errorsLibraryPath] stringByAppendingPathComponent: [NSString stringWithFormat:@"ios_error_%@_%@.log", nowString, [[NSUUID UUID] UUIDString]]];

    NSMutableArray *screenTraces = [NSMutableArray new];
    for (ScreenDetails *details in [[CrashOpsController shared] screenTracer].breadcrumbsReport) {
        [screenTraces addObject:[details toDictionary]];
    }

    NSDictionary *jsonDictionary = @{@"errorDetails": errorDetails,
                                     @"report":@{@"id": [NSNumber numberWithInteger: timestamp],
                                                 @"time": nowString},
                                     //@"details": [self generateReport: [NSException exceptionWithName:@"Error" reason:@"" userInfo:@{@"isFatal": NO}]],
                                     @"details": [self generateReport: nil],
                                     @"screenTraces": screenTraces,
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

    return didSave;
}

-(NSString *) errorsLibraryPath {
    if (errorsPath != nil) {
        return errorsPath;
    }

    NSString *path = [self.crashOpsLibraryPath stringByAppendingPathComponent: @"Errors"];

    BOOL isDir = YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Create folder failed %@", path);
        }
    }

    errorsPath = path;

    return errorsPath;
}

-(NSString *) tracesLibraryPath {
    if (tracesPath != nil) {
        return tracesPath;
    }

    NSString *path = [self.crashOpsLibraryPath stringByAppendingPathComponent: @"Traces"];

    BOOL isDir = YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Create folder failed %@", path);
        }
    }

    tracesPath = path;

    return tracesPath;
}

-(NSString *) crashOpsLibraryPath {
    if (libraryPath != nil) {
        return libraryPath;
    }

    NSString *path = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent: @"CrashOps"];

    BOOL isDir = YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            DebugLogArgs(@"Error: Create folder failed %@", path);
        }
    }

    libraryPath = path;

    return libraryPath;
}

-(NSMutableDictionary *) generateReport:(NSException *) exception {
    NSMutableDictionary *jsonReport = [NSMutableDictionary new];

    NSThread *current = [NSThread currentThread];
    [CrashOpsController safeDictionary: jsonReport addObject: [current description] forKey: @"currentThread"];

    NSMutableArray *stackTrace;

    if (exception) {
        stackTrace = exception.callStackSymbols.mutableCopy;
        [CrashOpsController safeDictionary: jsonReport addObject: exception.reason forKey: @"reason"];
        if (exception.userInfo) {
            [CrashOpsController safeDictionary: jsonReport addObject: exception.userInfo forKey: @"moreInfo"];
        }
    } else {
        stackTrace = [[NSThread callStackSymbols] mutableCopy];
        [stackTrace removeObjectAtIndex: 0];
    }

    [CrashOpsController safeDictionary: jsonReport addObject: stackTrace forKey: @"stackTrace"];

    [CrashOpsController safeDictionary: jsonReport addObject: CrashOps.shared.metadata forKey: @"metadata"];
    
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
            DebugLogArgs(@"Error: Create folder failed %@", path);
        }
    }

    instance.ipsFilesPath = path;

    return instance.ipsFilesPath;
}

static void ourExceptionHandler(NSException *exception) {
    [[CrashOpsController shared] handleException: exception];
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
    if (![jsonDictionary count]) {
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
    
    [CrashOpsController swizzleScreenAppearance];
}

// https://nshipster.com/method-swizzling/
+ (void) swizzleScreenAppearance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class vcClass = [UIViewController class];
        Class thisClass = [CrashOpsController class];

        SEL originalSelector = @selector(viewDidAppear:);
        SEL swizzledSelector = @selector(co_onViewAppeared:);

        Method originalMethod = class_getInstanceMethod(vcClass, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(thisClass, swizzledSelector);

        // Apple:
        // "Discussion:
//        'class_addMethod' will add an override of a superclass's implementation, but will not replace an existing implementation in this class (Good!). To change an existing implementation, use method_setImplementation.
//        An Objective-C method is simply a C function that take at least two arguments — 'self' (the executor instance) and 'cmd' (the selector)."
        BOOL didAddMethod =
            class_addMethod(vcClass,
                originalSelector,
                method_getImplementation(swizzledMethod),
                method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(thisClass,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

// The swizzled methods
-(void) co_onViewAppeared:(BOOL) animated {
    if (![CrashOps shared].isTracingScreens) return;
    // Hmmm... this line won't work although "NSHipster" said we should call it.
    //[self co_onViewAppeared:animated];

    if ([self isKindOfClass: [UIViewController class]]) {
        // ignoring warning: "Incompatible pointer types initializing 'UIViewController *' with an expression of type 'CrashOpsController *'"
        UIViewController *appearedViewController = self;
        [[[CrashOpsController shared] screenTracer] addViewController: appearedViewController];
        
//        [co_ToastMessage show: [NSString stringWithFormat:@"viewDidAppear: %@", appearedViewController] delayInSeconds: 2 onDone:^{
//            // [co_ToastMessage show: @"toast done presenting..." delayInSeconds: 10 onDone: nil];
//        }];

//        NSMutableArray *traces = [NSMutableArray new];
//        for (ScreenDetails *details in [[CrashOpsController shared] screenTracer].breadcrumbsReport) {
//            [traces addObject: [details toDictionary]];
//        }
//        NSString *jsonString = [CrashOpsController toJsonString:@{@"traces": traces}];

//        [co_ToastMessage show: [NSString stringWithFormat:@"traces so far: %@", jsonString] delayInSeconds:5 onDone: nil];
    }
}

+ (NSDictionary *) getDeviceInfo {
    UIDevice* device = [UIDevice currentDevice];
    struct utsname un;
    uname(&un);

    // Discussion: These two strings are different...
//    DebugLog([CrashOpsController advertisingIdentifierString]);
//    DebugLog([[device identifierForVendor] UUIDString]);

    CGRect screenSize = [[UIScreen mainScreen] bounds];
    
    return @{
      @"name" : [device name],
      @"screenSize": [NSString stringWithFormat:@"%ldx%ld", (long)((NSInteger)screenSize.size.width), (long)((NSInteger)screenSize.size.height)],
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

+ (BOOL) safeDictionary:(NSMutableDictionary *) safeDictionary addObject:(NSObject *) obj forKey: (id<NSCopying> _Nonnull) key {
    BOOL didAdd = NO;
    if (safeDictionary == nil) return didAdd;

    if (obj && key) {
        [safeDictionary setObject: obj forKey: key];
        didAdd = YES;
    } else {
        [CrashOpsController logInternalError: @"Prevented from adding a `nil` field!"];
    }
    
    return didAdd;
}


@end
