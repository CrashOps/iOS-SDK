//
//  CrashOpsController.m
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "CrashOps.h"
#import "CrashOpsController.h"

#import "AppleCrashReportGenerator.h"

#import "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor.h"
#include "KSCrashMonitorContext.h"
#import <KZCrash/KSCrash.h>
#import <KZCrash/KSCrashInstallationStandard.h>
#import <KZCrash/KSCrashInstallationConsole.h>
#import <sys/utsname.h>

#import <AdSupport/ASIdentifierManager.h>

#import <zlib.h>

typedef void(^FilesUploadCompletion)(NSInteger filesCount);

typedef void(^LogsUploadCompletion)(NSArray *reports);

@interface CrashOpsController()

@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, strong) NSString *libraryPath;
@property (nonatomic, strong) NSString *errorsPath;
@property (nonatomic, strong) NSString *ipsFilesPath;
@property (nonatomic, strong) NSObject *appFinishedLaunchObserver;
@property (nonatomic, strong) NSNumber *isEnabled_Optional;

@property (nonatomic, strong) NSArray *previousErrorLogFilesList;
@property (nonatomic, strong) NSArray *previousCrashLogFilesList;

@property (nonatomic) NSOperationQueue* coGlobalOperationQueue;
@property (nonatomic, assign) KSCrashMonitorAPI* crashMonitorAPI;
@property (nonatomic, assign) BOOL didAppFinishLaunching;
@property (nonatomic, assign) BOOL isUploading;

+(void) logInternalError:(NSString *) internalError;

@end

#define DebugLog(msg) if (CrashOps.isRunningOnDebugMode) { NSLog(msg); }
#define DebugLogArgs(msg, args) if (CrashOps.isRunningOnDebugMode) { NSLog(msg, args); }

@implementation CrashOpsController

/** Date formatter for Apple date format in crash reports. */
static NSDateFormatter* g_dateFormatter;
static NSString * const kClientId = @"co_ClientId";
static NSString * const kSdkIdentifier = @"com.crashops.sdk";

@synthesize libraryPath;
@synthesize errorsPath;
@synthesize appFinishedLaunchObserver;
@synthesize coGlobalOperationQueue;
@synthesize isEnabled;
@synthesize isEnabled_Optional;
@synthesize didAppFinishLaunching;
@synthesize isUploading;
@synthesize crashMonitorAPI;
@synthesize clientId;
@synthesize userDefaults;

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
        isUploading = NO;
        isEnabled = YES;
        userDefaults = [[NSUserDefaults alloc] initWithSuiteName: kSdkIdentifier];
        clientId = [[self userDefaults] stringForKey: kClientId];
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

- (void)onChangedHandler {
    [self uploadLogs];
}

- (void)setClientId:(NSString *)crashOpsClientId {
    // https://stackoverflow.com/questions/899209/how-do-i-test-if-a-string-is-empty-in-objective-c
    if (![crashOpsClientId length]) {
        return;
    }

    if ([crashOpsClientId length] > 100) {
        return;
    }

    if (![clientId length]) {
        clientId = crashOpsClientId;
        [[self userDefaults] setObject: clientId forKey: kClientId];
    } else {
        // TODO: Notify that client ID has already been set.
    }

    if ([clientId length]) {
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

+ (void) logInternalError:(NSString *) internalError {
    [[CrashOpsController shared] reportInternalError: internalError];
}

// TODO: Report this to our private analytics tool
- (void)reportInternalError:(NSString *) sdkError {
    DebugLogArgs(@"%@", sdkError);
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

    [self setupFromInfoPlist];
    //DebugLogArgs(@"App loaded, isJailbroken = %d", CrashOpsController.isJailbroken);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[CrashOpsController shared] uploadLogs];
    });
}

-(void) setupFromInfoPlist {
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
    
    if (CrashOps.isRunningOnDebugMode && config_isDisabledOnDebug) {
        isEnabled = NO;
    }

    if (!CrashOps.isRunningOnDebugMode && config_isDisabledOnRelease) {
        isEnabled = NO;
    }

    [CrashOps shared].isEnabled = isEnabled;
    [CrashOps shared].clientId = clientId;
}

- (NSArray *) errorLogFilesList {
    NSString *clientId = CrashOps.shared.clientId;
    if (!(clientId && [clientId length] > 0 && [clientId length] < 100)) {
        clientId = nil;
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
    if (basePath) {
        NSString *reportsPath = [basePath stringByAppendingPathComponent: @"Reports"];
        
        [[[CrashOpsController shared] coGlobalOperationQueue] addOperationWithBlock:^{
            NSString *clientId = [CrashOpsController shared].clientId;
            if (!(clientId && [clientId length] > 0 && [clientId length] < 100)) {
                clientId = nil;
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
                    [allReports setObject:logFileJson forKey:logFileUrlPath];
                }

                NSMutableArray *uploadTasks = [NSMutableArray new];
                // An old fashion, simplified, "synchronizer" :)
                LogsUploadCompletion completion = ^void(NSArray* reportPaths) {
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
                                    [[CrashOpsController shared] reportInternalError: [NSString stringWithFormat:@"Failed to delete report file, error: %@", error]];
                                }
                            }
                        }

                        static dispatch_once_t onceToken;
                        dispatch_once(&onceToken, ^{
                            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                [CrashOps shared].previousCrashReports(reportDictionaries);
                            }];
                        });
                    } else if ([reportPaths count] > 0) {
                        // Considered waiting to the first VC to appear (https://spin.atomicobject.com/2014/12/30/method-swizzling-objective-c/) but it's also won't solve all cases by the various developers out there.

                        DebugLog(@"Waiting to the host app's handler to be set...");
//                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                            [[CrashOpsController shared] uploadLogs]; // Bad solution, we won't use this solution for example...
//                        });
                    }
                    
                    if (onDone) {
                        onDone(reportPaths.count);
                    }
                };

                NSMutableArray *sentReports = [NSMutableArray new];

                for (NSURL *reportPath in allReports) {
                    NSString *reportJson = allReports[reportPath];
                    if (clientId) {
                        NSString *ipsFilePath = [AppleCrashReportGenerator generateIpsFile: reportPath];
                        NSDictionary *jsonDictionary = [CrashOpsController toJsonDictionary: reportJson];
                        NSDate *logTime = [AppleCrashReportGenerator crashDate: jsonDictionary];
                        NSString *reportId = [AppleCrashReportGenerator reportId: jsonDictionary];
                        NSString *timestamp = [CrashOpsController stringFromDate: logTime withFormat: nil];

                        NSData *fileData = [NSData dataWithContentsOfFile: ipsFilePath];
                        NSData *zipped = [CrashOpsController gzippedWithCompressionLevel: fileData];

                        if (!zipped) {
                            [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to zip log into gzip data, file path: %@", ipsFilePath]];
                            continue;
                        }

//                        NSString *fileName = [[[ipsFilePath lastPathComponent] componentsSeparatedByString:@"."] firstObject];
//                        if (!fileName || ![fileName length]) {
//                            [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to extract file name, file path: %@", reportPath.description]];
//                            continue;
//                        }

                        NSString *zipFileName = [NSString stringWithFormat:@"ios_crash_%@_%@.gzip", timestamp, reportId];

                        NSMutableURLRequest *request = [CrashOpsController prepareRequestMultipartFormData: zipped andFileName: zipFileName];

                        if (!request) {
                            [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to make request for file upload, file path: %@", ipsFilePath]];
                            continue;
                        }

                        [request addValue: clientId forHTTPHeaderField:@"crashops-client-id"];

                        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request completionHandler:^(NSData * _Nullable returnedData, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                            NSString *returnString = [[NSString alloc] initWithData: returnedData encoding: NSUTF8StringEncoding];
                            DebugLogArgs(@"%@", returnString);

                            BOOL wasRequestSuccessful = false;
                            if (response && [response isKindOfClass: [NSHTTPURLResponse class]]) {
                                NSInteger responseStatusCode = ((NSHTTPURLResponse *)response).statusCode;
                                wasRequestSuccessful = responseStatusCode >= 200 && responseStatusCode < 300;
                            }

                            if (wasRequestSuccessful) {
                                [sentReports addObject: reportPath];
                            } else {
                                [CrashOpsController logInternalError:@"Failed to upload!"];
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
//                    completion(sentReports);
                    completion(@[]);
                }

                for (NSURLSessionDataTask *uploadTask in uploadTasks) {
                    [uploadTask resume];
                }
            }
        }];
    }
}

- (void) uploadErrors:(FilesUploadCompletion) onDone {
    [[[CrashOpsController shared] coGlobalOperationQueue] addOperationWithBlock:^{
        NSString *clientId = [CrashOpsController shared].clientId;
        if (!(clientId && [clientId length] > 0 && [clientId length] < 100)) {
            clientId = nil;
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
                [allReports setObject:logFileJson forKey:logFileUrlPath];
            }

            NSMutableArray *uploadTasks = [NSMutableArray new];
            // An old fashion, simplified, "synchronizer" :)
            LogsUploadCompletion completion = ^void(NSArray* reportPaths) {
                if ([reportPaths count] > 0) {
                    NSMutableArray* reportDictionaries = [NSMutableArray new];
                    for (NSURL *reportPath in allReports) {
                        NSString *reportJson = allReports[reportPath];

                        if (reportJson) {
                            NSDictionary *jsonDictionary = [CrashOpsController toJsonDictionary: reportJson];

                            [reportDictionaries addObject: jsonDictionary];
                            NSError *error;
                            [[NSFileManager defaultManager] removeItemAtURL: reportPath error: &error];
                            if (error) {
                                [[CrashOpsController shared] reportInternalError: [NSString stringWithFormat:@"Failed to delete report file, error: %@", error]];
                            }
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

            NSMutableArray *sentReports = [NSMutableArray new];

            for (NSURL *reportPath in allReports) {
                NSString *reportJson = allReports[reportPath];
                if (clientId) {
                    NSData *fileData = [NSData dataWithContentsOfURL: reportPath];
                    NSData *zipped = [CrashOpsController gzippedWithCompressionLevel: fileData];
                    NSString *fileName = [[[reportPath lastPathComponent] componentsSeparatedByString:@"."] firstObject];
                    if (!fileName || ![fileName length]) {
                        [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to extract file name, file path: %@", reportPath.description]];
                        continue;
                    }

                    NSString *zipFileName = [NSString stringWithFormat:@"%@.gzip", fileName];

                    NSMutableURLRequest *request = [CrashOpsController prepareRequestMultipartFormData:zipped andFileName: zipFileName];

                    if (!request) {
                        [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to make request for file upload, file path: %@", reportPath]];
                        continue;
                    }

                    [request addValue: clientId forHTTPHeaderField:@"crashops-client-id"];

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
                //completion(sentReports);
                completion(@[]);
            }

            for (NSURLSessionDataTask *uploadTask in uploadTasks) {
                [uploadTask resume];
            }
        }
    }];
}

/** Uploads pending log files.
 *  Each upload bulk operation will occur one at a time.
 */
- (void) uploadLogs {
    if (![CrashOps shared].isEnabled) return;
    if (!clientId) return;

    if (isUploading) return;
    isUploading = true;

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

    [self uploadCrashes:^(NSInteger filesCount) {
        [uploadResults addObject: [NSNumber numberWithLong: filesCount]];
        if (uploadResults.count == 2) {
            NSInteger total = ((NSNumber*)[uploadResults objectAtIndex:0]).integerValue + ((NSNumber*)[uploadResults objectAtIndex:1]).integerValue;
            completion(total);
        }
    }];

    [self uploadErrors:^(NSInteger filesCount) {
        [uploadResults addObject:[NSNumber numberWithLong:filesCount]];
        if (uploadResults.count == 2) {
            NSInteger total = ((NSNumber*)[uploadResults objectAtIndex:0]).integerValue + ((NSNumber*)[uploadResults objectAtIndex:1]).integerValue;
            completion(total);
        }
    }];
}

+ (NSMutableURLRequest *) prepareRequestMultipartFormDataOfUrl:(NSURL *)filePath {
    NSData *fileData = [NSData dataWithContentsOfURL: filePath];

    if (!fileData) {
        return nil;
    }

    return [CrashOpsController prepareRequestMultipartFormData: fileData andFileName:[filePath lastPathComponent]];
}

+ (NSMutableURLRequest *) prepareRequestMultipartFormDataOfFile:(NSString *)filePath {
    NSData *fileData = [NSData dataWithContentsOfFile: filePath];

    if (!fileData) {
        return nil;
    }

    return [CrashOpsController prepareRequestMultipartFormData: fileData andFileName:[filePath lastPathComponent]];
}

+ (NSMutableURLRequest *) prepareRequestMultipartFormData:(NSData *)fileData andFileName:(NSString *) fileName {
    
    NSString *serverUrlString = @"https://us-central1-crash-logs.cloudfunctions.net/uploadLog";

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: serverUrlString]];

    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request setHTTPShouldHandleCookies:NO];
    [request setTimeoutInterval:60];
    [request setHTTPMethod:@"POST"];
    
    NSString *boundary = @"unique-consistent-string";
    
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue: contentType forHTTPHeaderField: @"Content-Type"];
    
    NSMutableData *postBody = [NSMutableData data];
    
    if (fileData) {
        // https://gist.github.com/mombrea/8467128
        [postBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [postBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=%@; filename=%@\r\n", @"logFile", fileName] dataUsingEncoding: NSUTF8StringEncoding]];
        [postBody appendData:[@"Content-Type: text/plain\r\n\r\n" dataUsingEncoding: NSUTF8StringEncoding]];
        [postBody appendData: fileData];
        [postBody appendData:[[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    [postBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    [request setHTTPBody: postBody];

    if (![postBody length]) {
        return nil;
    }

    NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[postBody length]];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    
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

- (BOOL) logError:(NSDictionary *) errorDetails {
    if (!errorDetails) return NO;
    if (![errorDetails count]) return NO;

    NSDate *now = [NSDate date];
    NSTimeInterval timeMilliseconds = [now timeIntervalSince1970] * 1000;
    NSInteger timestamp = ((NSInteger) timeMilliseconds);

    NSString *nowString = [CrashOpsController stringFromDate: now withFormat: @"yyyy-MM-dd-HH-mm-ss-SSS_ZZZ"];

    NSString *filePath = [[self errorsLibraryPath] stringByAppendingPathComponent: [NSString stringWithFormat:@"ios_error_%@_%@.log", nowString, [[NSUUID UUID] UUIDString]]];

    NSDictionary *jsonDictionary = @{@"errorDetails": errorDetails,
                                     @"report":@{@"id": [NSNumber numberWithInteger: timestamp],
                                                 @"time": nowString},
                                     //@"details": [self generateReport: [NSException exceptionWithName:@"Error" reason:@"" userInfo:@{@"isFatal": NO}]],
                                     @"details": [self generateReport: nil],
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

-(NSMutableDictionary *) generateReport:(NSException *) exception {
    NSMutableDictionary *jsonReport = [NSMutableDictionary new];

    NSThread *current = [NSThread currentThread];
    [jsonReport setObject: [current description] forKey: @"currentThread"];

    NSMutableArray *stackTrace;

    if (exception) {
        stackTrace = exception.callStackSymbols.mutableCopy;
        [jsonReport setObject: exception.reason forKey: @"reason"];
        if (exception.userInfo) {
            [jsonReport setObject: exception.userInfo forKey: @"moreInfo"];
        }
    } else {
        stackTrace = [[NSThread callStackSymbols] mutableCopy];
        [stackTrace removeObjectAtIndex: 0];
    }

    [jsonReport setObject: stackTrace forKey: @"stackTrace"];

    [jsonReport setObject: CrashOps.shared.metadata forKey: @"metadata"];
    
//    [jsonReport setObject: [NSBundle allFrameworks] forKey: @"allFrameworks"];

    return jsonReport;
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

static void ourExceptionHandler(NSException *exception) {
    [[CrashOpsController shared] handleException: exception];
}

+(NSString *) toJsonString:(NSDictionary *) jsonDictionary {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject: jsonDictionary options: NSJSONWritingPrettyPrinted error: &error];

    NSString* jsonString = [[NSString alloc] initWithData: jsonData encoding: NSUTF8StringEncoding];
    DebugLogArgs(@"jsonString: %@", jsonString);
    
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

+(void) initialize {
    DebugLog(@"App is loading...");
    g_dateFormatter = [[NSDateFormatter alloc] init];
    [g_dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
}

+ (void)load {
    [[CrashOpsController shared] onAppIsLoading];
    DebugLog(@"CrashOps library is being loaded");
}

+ (NSDictionary *) getDeviceInfo {
    UIDevice* device = [UIDevice currentDevice];
    struct utsname un;
    uname(&un);

    // Discussion: These two strings are different...
//    DebugLog([CrashOpsController advertisingIdentifierString]);
//    DebugLog([[device identifierForVendor] UUIDString]);

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
