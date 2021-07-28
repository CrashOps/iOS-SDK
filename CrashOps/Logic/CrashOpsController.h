//
//  CrashOpsController.h
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#ifndef _CRASHOPS_STUFF
#define _co_timestamp_milliseconds() [[NSDate new] timeIntervalSince1970] * 1000
#define _CRASHOPS_STUFF
#else
#endif

#import <Foundation/Foundation.h>
#import "ScreenTracer.h"
#import "ScreenDetails.h"

typedef void (^VoidCallback)(void);

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
*  Generates session details of the application running session.
*/
-(NSDictionary *) generateSessionDetails;

/**
*  CrashOps library file system path.
*/
-(NSString *) crashOpsLibraryPath;

/**
*  Logs non-fatal errors.
*/
- (BOOL) logErrorWithTitle:(NSString *) errorTitle andDetails:(NSDictionary *) errorDetails;

/**
*  Notifies that the host app changed its handler.
*/
- (void) onHandlerChanged;

-(ScreenTracer *) screenTracer;

+ (NSString *) deviceId;

+(BOOL) isDebugModeEnabled;

+(NSString *) ipsFilesLibraryPath;

+(NSDictionary *) toJsonDictionary:(NSString *) jsonString;

+(NSString *) toJsonString:(NSDictionary *) jsonDictionary;

+(NSData *) toJsonData:(NSDictionary *) jsonDictionary;

-(void) flushToDisk:(ScreenDetails *) screenDetails;

+(NSString *) screenTracesFolderFromSessionId:(NSString *) sessionId;

+ (void) logInternalError:(NSString *) sdkError;

+(void) asyncLoopArray:(NSArray *) elements iterationBody:(void (^)(id element, VoidCallback carryOn)) iterationBody onDone:(VoidCallback) onDone;

@end


@interface NSMutableDictionary<KeyType, ObjectType> (CO_NilSafeDictionary)

- (BOOL) co_setOptionalObject:(ObjectType)anObject forKey:(KeyType <NSCopying>)aKey;

@end
