//
//  CrashOpsExtendedViewController+UIViewController.h
//  CrashOps
//
//  Created by CrashOps on 04/05/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIViewController (co_CrashOpsExtendedViewController)

-(void) co_onViewAppeared:(BOOL) animated;

/**
 Will work only if the UIViewController subclass was calling its super class method: `super.viewDidAppear(animated)`.
*/
+(void) swizzleScreenAppearance;

@end
