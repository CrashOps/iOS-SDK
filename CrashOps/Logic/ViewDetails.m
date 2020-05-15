//
//  ViewDetails.m
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "ViewDetails.h"

@interface ViewDetails()

/// A list of `ViewDetails` objects
@property (nonatomic, strong) NSMutableArray *children;
@property (nonatomic, strong) NSString *className;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, assign) CGSize dimensions;
@property (nonatomic, assign) CGPoint position;

@end

@implementation ViewDetails

- (instancetype)initWithView:(UIView *)view depth:(NSInteger) depth {
    self = [super init];

    if (self) {
        _children = [NSMutableArray new];
        _className = [[view class] description];
        _depth = depth;
        _dimensions = view.frame.size;
        _position = view.frame.origin;

        for (UIView *subview in view.subviews) {
            [_children addObject: [[ViewDetails alloc] initWithView: subview depth: depth + 1]];
        }
    }

    return self;
}

- (NSString *)className {
    return _className;
}

- (CGSize)dimensions {
    return _dimensions;
}

- (CGPoint)position {
    return _position;
}

- (NSInteger) depth {
    return _depth;
}

- (BOOL) isLeaf {
    return _children.count == 0;
}

- (NSString *)description {
    NSString *detailsDescription = [NSString stringWithFormat:@"{'className': %@, 'dimensions': (%.2f x %.2f)", _className, _dimensions.width, _dimensions.height];

    if ([self isLeaf] == NO) {
        NSString *children = @"[";
        for (ViewDetails *details in _children) {
            children = [[children stringByAppendingString: [details description]] stringByAppendingString: @", "];
        }
        children = [children stringByAppendingString: @"]"];

        detailsDescription = [NSString stringWithFormat:@", 'children: %@'}", children];
    } else {
        detailsDescription = [NSString stringWithFormat:@"}"];
    }

    return detailsDescription;
}

- (NSDictionary *)toDictionary {
    return [ViewDetails _toDictionary: self];
}

+(NSDictionary *) _toDictionary:(ViewDetails *) viewDetails {
    NSMutableDictionary *viewDetailsDictionary = [NSMutableDictionary new];
    [viewDetailsDictionary setObject: [viewDetails className] forKey: @"className"];
    [viewDetailsDictionary setObject: [NSNumber numberWithInteger:[viewDetails depth]] forKey: @"depth"];

    NSMutableDictionary *dimensionsDictionary = [NSMutableDictionary new];
    [dimensionsDictionary setObject: [NSNumber numberWithInteger: (NSInteger)[viewDetails dimensions].width] forKey: @"width"];
    [dimensionsDictionary setObject: [NSNumber numberWithInteger: (NSInteger)[viewDetails dimensions].height] forKey: @"height"];
    [viewDetailsDictionary setObject: dimensionsDictionary forKey: @"dimensions"];

    NSMutableDictionary *positionDictionary = [NSMutableDictionary new];
    [positionDictionary setObject: [NSNumber numberWithInteger: (NSInteger)[viewDetails position].x] forKey: @"x"];
    [positionDictionary setObject: [NSNumber numberWithInteger: (NSInteger)[viewDetails position].y] forKey: @"y"];
    [viewDetailsDictionary setObject: positionDictionary forKey: @"position"];

    if ([viewDetails isLeaf] == NO) {
        NSMutableArray *children = [NSMutableArray new];
        for (ViewDetails *details in viewDetails.children) {
            [children addObject:[details toDictionary]];
        }

        if ([children count]) {
            [viewDetailsDictionary setObject: children forKey: @"children"];
        }
    }

    return viewDetailsDictionary;
}

@end
