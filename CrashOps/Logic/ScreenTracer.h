//
//  ScreenTracer.h
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol ViewControllerTracer <NSObject>

/// A list of `ScreenDetails` objects
-(NSArray *) breadcrumbsReport;

@end


@interface ScreenTracer: NSObject<ViewControllerTracer>

- (void) addViewController: (UIViewController *) viewController;

@end
