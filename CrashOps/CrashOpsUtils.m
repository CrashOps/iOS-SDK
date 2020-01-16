//
//  CrashOpsUtils.m
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "CrashOps.h"
#import "CrashOpsUtils.h"
#import "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor.h"
#include "KSCrashMonitorContext.h"
#import <KSCrash/KSCrash.h>
#import <KSCrash/KSCrashInstallationStandard.h>
#import <KSCrash/KSCrashInstallationConsole.h>
#import <KSCrash/KSCrashInstallationEmail.h>

typedef void(^ReportsUploadCompletion)(NSArray *reports);

@interface CrashOpsUtils()

@property (nonatomic, strong) NSString *libraryPath;
@property (nonatomic, strong) NSObject *appFinishedLaunchObserver;
@property (nonatomic) NSOperationQueue* coGlobalOperationQueue;

@end

@implementation CrashOpsUtils

@synthesize libraryPath;
@synthesize appFinishedLaunchObserver;
@synthesize coGlobalOperationQueue;

NSUncaughtExceptionHandler *oldHandler;

// Singleton implementation in Objective-C
__strong static CrashOpsUtils *_shared;
+ (CrashOpsUtils *)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CrashOpsUtils alloc] init];
    });
    
    return _shared;
}

- (id)init {
    if (self = [super init]) {
        coGlobalOperationQueue = [[NSOperationQueue alloc] init];
    }

    return self;
}

/**
 Using conditional compilation flags: https://miqu.me/blog/2016/07/31/xcode-8-new-build-settings-and-analyzer-improvements/
 */
+(BOOL)isRunningReleaseVersion {
#ifdef DEBUG
    return NO;
#else
    return YES;
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

-(void) onAppLoaded {
    NSLog(@"App loaded, isJailbroken = %d", CrashOpsUtils.isJailbroken);
    oldHandler = NSGetUncaughtExceptionHandler();

    NSSetUncaughtExceptionHandler(exceptionHandlerPtr);

    // Wait for app to finish launch and then...
    appFinishedLaunchObserver = [[NSNotificationCenter defaultCenter] addObserverForName: UIApplicationDidFinishLaunchingNotification object: nil queue: nil usingBlock:^(NSNotification * _Nonnull note) {
        [[CrashOpsUtils shared] configureAdvancedSettings];

        [[NSNotificationCenter defaultCenter] removeObserver: [[CrashOpsUtils shared] appFinishedLaunchObserver]];

        if ([[KSCrash sharedInstance] respondsToSelector: @selector(basePath)]) {
            NSString *basePath = [[KSCrash sharedInstance] performSelector: @selector(basePath)];
            NSString *reportsPath = [basePath stringByAppendingPathComponent: @"Reports"];
            if ([[NSFileManager defaultManager] fileExistsAtPath: reportsPath]) {
                NSArray *filesList = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString: reportsPath] includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsHiddenFiles error: nil];

                [[[CrashOpsUtils shared] coGlobalOperationQueue]addOperationWithBlock:^{
                    NSMutableArray *allReports = [NSMutableArray new];

                    for (NSURL *logFileUrlPath in filesList) {
                        NSLog(@"%@", logFileUrlPath);
                        
                        NSString *logFileJson = [[NSString alloc] initWithData: [NSData dataWithContentsOfURL: logFileUrlPath] encoding: NSUTF8StringEncoding];
                        [allReports addObject: logFileJson];
                    }

                    NSMutableArray *uploadTasks = [NSMutableArray new];
                    // An old fashion, simplified, "synchronizer" :)
                    ReportsUploadCompletion completion = ^void(NSArray* reports){
                        if ([reports count] > 0 && [CrashOps shared].previousCrashReports) {
                            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                [CrashOps shared].previousCrashReports(reports);
                            }];
                        }
                    };

                    NSMutableArray *sentReports = [NSMutableArray new];

                    for (NSString *reportJson in allReports) {
                        NSString *serverUrlString = @"https://us-central1-crash-logs.cloudfunctions.net/storeCrashReport";
                        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
                        [request setURL:[NSURL URLWithString: serverUrlString]];
                        [request setHTTPMethod:@"POST"];

                        NSMutableData *body = [NSMutableData data];

                        NSString *contentType = [NSString stringWithFormat:@"application/json; charset=utf-8"];
                        [request addValue:contentType forHTTPHeaderField:@"Content-Type"];

                        [body appendData:[[NSString stringWithString: reportJson] dataUsingEncoding: NSUTF8StringEncoding]];

                        [request setHTTPBody:body];

                        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request completionHandler:^(NSData * _Nullable returnedData, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                            NSString *returnString = [[NSString alloc] initWithData: returnedData encoding: NSUTF8StringEncoding];
                            NSLog(@"%@", returnString);
                            
                            NSDictionary *jsonDictionary = [CrashOpsUtils toJsonDictionary: reportJson];
                            [sentReports addObject: jsonDictionary];

                            [uploadTasks removeLastObject];
                            if (uploadTasks.count == 0) {
                                completion(sentReports);
                            }
                        }];
                        
                        [uploadTasks addObject: task];
                    }

                    for (NSURLSessionDataTask *uploadTask in uploadTasks) {
                        [uploadTask resume];
                    }
                }];
            }
        }
    }];
    
    KSCrashInstallationStandard* installation = [KSCrashInstallationStandard sharedInstance];
    [installation install];

    /* Perry's additions to help with tests */
    KSCrashMonitorAPI* crashMonitorAPI = kscm_nsexception_getAPI();
    crashMonitorAPI->setEnabled(YES);
    /* Perry's additions to help with tests */
}

// ======================================================================
#pragma mark - Advanced Crash Handling (optional) -
// ======================================================================

- (void) configureAdvancedSettings {
    KSCrash* handler = [KSCrash sharedInstance];

    if ([CrashOps shared].metadata && [[CrashOps shared].metadata count]) {
        handler.userInfo = [[CrashOps shared].metadata copy];
    }

    if ([CrashOps shared].excludeClassesDetails) {
        // Do not introspect these classes
        handler.doNotIntrospectClasses = [[CrashOps shared].excludeClassesDetails copy];
    }
}

-(void) handleException:(NSException *) exception {
    if (oldHandler) {
        oldHandler(exception);
    }

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

    NSString *toJsonString = [CrashOpsUtils toJsonString: jsonReport];
    NSLog(@"%@", toJsonString);

    NSData *jsonData = [CrashOpsUtils toJsonData: jsonReport];

    BOOL didWrite = [jsonData writeToFile: [[self crashOpsLibraryPath] stringByAppendingPathComponent: nowString] options: NSDataWritingAtomic error: &error];
    if (!didWrite || error) {
        NSLog(@"Failed to save with error %@", error);
    } else {
        NSLog(@"Saved :)");
    }

    NSLog(@"Upload to server... ");

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
    [[CrashOpsUtils shared] handleException: exception];
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
    [[CrashOpsUtils shared] onAppLoaded];
}

+(void)initialize {
    NSLog(@"App loaded");
}

@end
