//
//  DebugToastMessage.m
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "DebugToastMessage.h"

@implementation co_ToastMessage

-(void) removeSelf {
    [UIView animateWithDuration: 0.8 animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(2, 2);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (self.callback) {
            self.callback();
        }
    }];
}

/// This method is FOR DEBUG PURPOSES only and it won't be able to run in release builds.
+(void) show: (NSString *) messageText delayInSeconds:(NSTimeInterval) delay onDone:(void (^)(void)) callback {
    if (![co_ToastMessage isRunningOnDebugMode]) {
        if (callback) {
            callback();
        }

        return;
    }

    if (!NSThread.isMainThread) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [co_ToastMessage show: messageText delayInSeconds: delay onDone: callback];
        }];

        return;
    }

    UIWindow *appWindow = UIApplication.sharedApplication.keyWindow;
    if (!appWindow) {
        if (callback) {
            callback();
        }

        return;
    }

    // Personally we sould prefer to use autolayout (constraints) but we rather not too, because we never can predeict wich kind of project will run this SDK, and the results are satisfying FOR DEBUG PURPOSES.
    CGFloat width = MIN(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height);
    co_ToastMessage *toastMessage = [[co_ToastMessage alloc] initWithFrame: (CGRectMake(width * 0.1, width * 0.1, width * 0.8, width * 0.8))];
    toastMessage.delay = delay;
    toastMessage.messageLabel = [[UILabel alloc] initWithFrame: (CGRectMake(0, 0, width * 0.8, width * 0.8))];
    toastMessage.messageLabel.textAlignment = NSTextAlignmentCenter;
    toastMessage.messageLabel.text = messageText;
    toastMessage.messageLabel.textColor = [UIColor whiteColor];
    toastMessage.messageLabel.numberOfLines = 0;
    toastMessage.layer.cornerRadius = 5;
    toastMessage.layer.masksToBounds = YES;

    [toastMessage addSubview: toastMessage.messageLabel];
    toastMessage.userInteractionEnabled = NO;
    toastMessage.backgroundColor = [[UIColor darkGrayColor] colorWithAlphaComponent: 0.8];

    toastMessage.callback = callback;

    toastMessage.alpha = 0;
    [appWindow addSubview: toastMessage];
    toastMessage.transform = CGAffineTransformMakeScale(0.1, 0.1);

    [UIView animateWithDuration: 0.3 animations:^{
        toastMessage.alpha = 1;
        toastMessage.transform = CGAffineTransformMakeScale(1, 1);
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toastMessage removeSelf];
    });

//        toastMessage.translatesAutoresizingMaskIntoConstraints = false
//        let bottomConstraint = NSLayoutConstraint(item: toastMessage, attribute: .bottom, relatedBy: .equal, toItem: toastMessage.superview, attribute: .bottom, multiplier: 1, constant: -30.0)
//        let leftConstraint = NSLayoutConstraint(item: toastMessage, attribute: .left, relatedBy: .equal, toItem: toastMessage.superview, attribute: .left, multiplier: 1, constant: 10.0)
//        let rightConstraint = NSLayoutConstraint(item: toastMessage, attribute: .right, relatedBy: .equal, toItem: toastMessage.superview, attribute: .right, multiplier: 1, constant: -10.0)
//        appWindow/* which is: toastMessage.superview */.addConstraints([bottomConstraint, leftConstraint, rightConstraint])
//
//        let heightConstraint = NSLayoutConstraint(item: toastMessage, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .height, multiplier: 1.0, constant: 0.3 * max(appWindow.frame.height, appWindow.frame.width))
//        toastMessage.addConstraint(heightConstraint)

}

+(BOOL)isRunningOnDebugMode {
#ifdef DEBUG
    return YES;
#else
    return NO;
#endif
}

@end
