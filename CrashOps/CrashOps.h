//
//  CrashOps.h
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <Foundation/Foundation.h>

//! Project version number for CrashOps.
FOUNDATION_EXPORT double CrashOpsVersionNumber;

//! Project version string for CrashOps.
FOUNDATION_EXPORT const unsigned char CrashOpsVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <CrashOps/PublicHeader.h>


NS_ASSUME_NONNULL_BEGIN

typedef void(^PreviousReportsHandler)(NSArray *reports);

/**
 *  This class exposes the Answers Events API, allowing you to track key
 *  user user actions and metrics in your app.
 */
@interface CrashOps : NSObject

/**
 *  An optional block / closure that enables the host app to catch exceptions using our SDK.
*/
@property (nonatomic, assign) NSUncaughtExceptionHandler *appExceptionHandler;

/**
 *  The client ID received by CrashOps customer services.
*/
@property (nonatomic, strong) NSString *clientId;

/**
 *  Determines whether the SDK is enabled or not, it's set to true by default.
 *  This value may also be optionally changed via the 'CrashOpsConfig-info.plist' file.
*/
@property (nonatomic, assign) BOOL isEnabled;

/**
 *  Enables adding metadata to each report, this data will be available under the "User" key.
*/
@property (nonatomic, strong) NSMutableDictionary *metadata;

/**
 *  Experimental: use this array to exlude details from this class.
*/
@property (nonatomic, strong) NSMutableArray *excludeClassesDetails;

/**
 *  Allows the developer get previous crash reports.
*/
@property (nonatomic) PreviousReportsHandler previousCrashReports;

/**
 *  Shares the singleton object to provide façade of SDK's APIs.
*/
+(CrashOps *) shared;

/**
 *  Deletes all previous collected reports.
*/
-(void) deleteOldReports;

/**
 *  Causes a crash for testing purposes.
 */
-(void) crash;

/**
 *  Causes a crash due to exception for testing purposes.
 */
-(void) throwException;

/**
*  Logs non-fatal errors.
*/
-(BOOL) logError:(NSDictionary *) errorDetails;

+(BOOL) isRunningOnDebugMode;

@end

NS_ASSUME_NONNULL_END
