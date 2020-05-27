//
//  CrashOpsExtendedViewController+UIViewController.m
//  CrashOps
//
//  Created by CrashOps on 04/05/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "CrashOpsExtendedViewController+UIViewController.h"
#import "ScreenDetails.h"
#import "CrashOpsController.h"
#import "CrashOps.h"
#import "DebugToastMessage.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation UIViewController (co_CrashOpsExtendedViewController)

-(CrashOpsController *) crashOpsController {
    return [CrashOpsController shared];
}

// Read more at: https://nshipster.com/method-swizzling/
+ (void) swizzleScreenAppearance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class vcClass = [UIViewController class];

        SEL originalSelector = @selector(viewDidAppear:);
        SEL swizzledSelector = @selector(co_onViewAppeared:);

        Method originalMethod = class_getInstanceMethod(vcClass, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(vcClass, swizzledSelector);

        // Apple:
        // "Discussion:
//        'class_addMethod' will add an override of a superclass's implementation, but will not replace an existing implementation in this class (Good!). To change an existing implementation, use method_setImplementation.
//        An Objective-C method is simply a C function that take at least two arguments — 'self' (the executor instance) and 'cmd' (the selector)."
        BOOL didAddMethod =
            class_addMethod(vcClass,
                originalSelector,
                method_getImplementation(swizzledMethod),
                method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(vcClass,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

// The swizzled method
-(void) co_onViewAppeared:(BOOL) animated {
    [self co_onViewAppeared: animated]; // Don't worry about it... 😏 it will call the original base method
    if (![CrashOps shared].isTracingScreens) return;
    
    if ([self isKindOfClass: [UIViewController class]]) {
        UIViewController *appearedViewController = self;
        [[self.crashOpsController screenTracer] addViewController: appearedViewController];
    }
}

@end
