//
//  CrashOpsExtendedViewController+UIViewController.h
//  CrashOps
//
//  Created by CrashOps on 04/05/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface COThrottler: NSObject
@end

@interface CrashOpsUtils : NSObject

+ (void)replaceImplementationOfKnownSelector:(SEL)originalSelector onClass:(Class)class withBlock:(id)block swizzledSelector:(SEL)swizzledSelector;

+ (SEL)swizzledSelectorForSelector:(SEL)selector;

@end

@interface UIViewController (co_CrashOpsExtendedViewController)

-(void) co_onViewAppeared:(BOOL) animated;

/**
 Will work only if the UIViewController subclass was calling its super class method: `super.viewDidAppear(animated)`.
*/
+(void) swizzleScreenAppearance;

@end


@interface UIApplication (co_CrashOpsExtendedResponder)

+ (void) swizzleDeviceShake;

@end

