//
//  ViewDetails.h
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewDetails: NSObject

- (instancetype)initWithView:(UIView *) view depth:(NSInteger) depth;

//-(NSString *) className;
//-(CGPoint) position;
//-(CGSize) dimensions;

-(NSDictionary *) toDictionary;

@end
