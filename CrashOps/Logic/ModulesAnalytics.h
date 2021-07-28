//
//  ModulesAnalytics.h
//  CrashOps
//
//  Created by CrashOps on 02/12/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CrashOpsController.h"

/**
 A private class that is responsible for modules / frameworks analytics.
 */
@interface ModulesAnalytics: NSObject

+(void) initiateWithController:(CrashOpsController *) controller;
+(NSMutableURLRequest *) prepareRequestWithBody:(NSDictionary *) bodyDictionary forEndpoint: (NSString *) apiEndpoint;

@end
