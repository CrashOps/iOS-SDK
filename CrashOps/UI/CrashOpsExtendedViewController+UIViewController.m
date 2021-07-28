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

typedef void(^VoidCallback)(void);

@interface COThrottler ()

@property (nonatomic, strong) NSTimer *throttleTimer;

@end

@implementation COThrottler

-(void)throttle:(NSTimeInterval) seconds operation: (VoidCallback) operation {
    if (!operation) return;

    [self.throttleTimer invalidate];
    self.throttleTimer = [NSTimer timerWithTimeInterval:seconds target:self selector:@selector(onTimerEnded:) userInfo: operation repeats: NO];

//    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSRunLoop mainRunLoop] addTimer: self.throttleTimer forMode: NSRunLoopCommonModes];
//    });
}

-(void)onTimerEnded:(NSTimer *)timer {
    if (timer != self.throttleTimer) return;
    if (!self.throttleTimer) return;

    self.throttleTimer = nil;

    VoidCallback operation = timer.userInfo;
    if (!operation) return;

    operation();
}

-(void)dispose {
    [self.throttleTimer invalidate];
    self.throttleTimer = nil;
}

@end

@implementation CrashOpsUtils

static NSMutableDictionary *throttlers;

+ (void)load {
    throttlers = [NSMutableDictionary new];
}

+(void)throttle:(NSTimeInterval) seconds withKey:(NSString *) key operation: (void (^)(void)) operation {
    if (!operation) return;

    COThrottler *throttler = throttlers[key];
    [throttler dispose];
    throttler = [COThrottler new];
    throttlers[key] = throttler;
    [throttler throttle:seconds operation:operation];
}

+ (void)replaceImplementationOfKnownSelector:(SEL)originalSelector onClass:(Class)class withBlock:(id)block swizzledSelector:(SEL)swizzledSelector
{
    // This method is only intended for swizzling methods that are know to exist on the class.
    // Bail if that isn't the case.
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    if (!originalMethod) {
        return;
    }
    
    IMP implementation = imp_implementationWithBlock(block);
    class_addMethod(class, swizzledSelector, implementation, method_getTypeEncoding(originalMethod));
    Method newMethod = class_getInstanceMethod(class, swizzledSelector);
    method_exchangeImplementations(originalMethod, newMethod);
}

+ (SEL)swizzledSelectorForSelector:(SEL)selector {
    return NSSelectorFromString([NSString stringWithFormat:@"_crashops_swizzle_%x_%@", arc4random(), NSStringFromSelector(selector)]);
}

@end

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
