//
//  CrashOpsController.h
//  CrashOps
//
//  Created by CrashOps on 01/01/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 A private class that is responsible on our core actions.
 */
@interface CrashOpsController: NSObject

/**
 *  The client ID received by CrashOps customer services.
*/
@property (nonatomic, strong) NSString *clientId;

/**
 *  Determines whether the SDK is enabled or not, it's set to true by default.
*/
@property (nonatomic, assign) BOOL isEnabled;

/**
*  Logs non-fatal errors.
*/
- (BOOL) logError:(NSDictionary *) errorDetails;

@end
