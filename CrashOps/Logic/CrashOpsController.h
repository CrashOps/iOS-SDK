//
//  CrashOpsController.h
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#ifndef _CRASHOPS_STUFF
#define _timestamp_milliseconds() [[NSDate new] timeIntervalSince1970] * 1000
#define _CRASHOPS_STUFF
#else
#endif

#import <Foundation/Foundation.h>
#import "ScreenTracer.h"
#import "ScreenDetails.h"

/**
 A private class that is responsible on our core actions.
 */
@interface CrashOpsController: NSObject

/**
 *  Your application key, received by CrashOps services.
*/
@property (nonatomic, strong) NSString *appKey;

/**
 *  Determines whether the SDK is enabled or not, it's set to `true` by default.
*/
@property (nonatomic, assign) BOOL isEnabled;

+ (CrashOpsController *) shared;

/**
*  CrashOps library file system path.
*/
-(NSString *) crashOpsLibraryPath;

/**
*  Logs non-fatal errors.
*/
- (BOOL) logError:(NSDictionary *) errorDetails;

/**
*  Notifies that the host app changed its handler.
*/
- (void) onHandlerChanged;

-(ScreenTracer *) screenTracer;

+(BOOL) isDebugModeEnabled;

+(NSString *) ipsFilesLibraryPath;

+(NSDictionary *) toJsonDictionary:(NSString *) jsonString;

+(NSString *) toJsonString:(NSDictionary *) jsonDictionary;

-(void) flushToDisk:(ScreenDetails *) screenDetails;

+(NSString *) screenTracesFolderFromSessionId:(NSString *) sessionId;

+ (void) logInternalError:(NSString *) sdkError;

@end


@interface NSMutableDictionary<KeyType, ObjectType> (CO_NilSafeDictionary)

- (BOOL) co_setOptionalObject:(ObjectType)anObject forKey:(KeyType <NSCopying>)aKey;

@end
