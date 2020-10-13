//
//  ScreenTracer.h
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol ViewControllerTracer <NSObject>

/// Loads a list of `ScreenDetails` objects from disk, according to session ID.
+(NSArray *) tracesReportForSessionId:(NSString *) sessionId;

@end


@interface ScreenTracer: NSObject<ViewControllerTracer>

- (void) addViewController: (UIViewController *) viewController;
+(NSArray *) tracesReportForSessionId:(NSString *) sessionId;

@end
