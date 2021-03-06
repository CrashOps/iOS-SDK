//
//  ScreenDetails.h
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ScreenDetails: NSObject

-(instancetype) initWithViewController:(UIViewController *) viewController;

/// Note: This timestamp is actually in milliseconds, unlike Apple's common representation (as seconds).
-(NSUInteger) timestamp;

-(NSDictionary *) toDictionary;

@end
