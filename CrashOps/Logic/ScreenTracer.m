//
//  ScreenTracer.m
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "ScreenTracer.h"
#import "ScreenDetails.h"
#import "CrashOpsController.h"

@implementation ScreenTracer

- (instancetype)init
{
    self = [super init];

    if (self) {
        //
    }

    return self;
}

-(void) addViewController:(UIViewController *)viewController {
    ScreenDetails* screenDetails = [[ScreenDetails alloc] initWithViewController: viewController];

    [[CrashOpsController shared] flushToDisk: screenDetails];
}

/**
Creates a separated screen traces details file so CrashOps won't interrupt KZCrash logging operations.
Later (on next app launch) CrashOps will merge these traces with the crash event that created here.
*/
+(NSArray *) tracesReportForSessionId:(NSString *) sessionId {
    NSMutableArray *allTraces = [NSMutableArray new];
    if (!sessionId) { return allTraces; }
    if (![sessionId length]) { return allTraces; }

    NSString *screenTracesFolderPath = [CrashOpsController screenTracesFolderFromSessionId: sessionId];

    NSArray *screenTraceFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: screenTracesFolderPath error: nil];

    if ([screenTraceFiles count]) {
        for (NSString *screenTraceFile in screenTraceFiles) {
            NSString *screenTraceFilePath = [screenTracesFolderPath stringByAppendingPathComponent: screenTraceFile];
            
            NSString *traceJsonString = [NSString stringWithContentsOfFile: screenTraceFilePath encoding: NSUTF8StringEncoding error: nil];
            [allTraces addObject: [CrashOpsController toJsonDictionary: traceJsonString]];
        }
    }

    if ([screenTraceFiles count] != [allTraces count]) {
        [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed extract all screen traces from trace files: %@", screenTraceFiles]];
    }

    return [allTraces copy];
}

@end
