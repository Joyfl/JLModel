//
//  JLModel.h
//  JLModel
//
//  Created by 전수열 on 13. 10. 10..
//  Copyright (c) 2013년 MyFoodList. All rights reserved.
//

#import <Foundation/Foundation.h>

#define Model(__className) \
@protocol __className <NSObject>\
@end

#define Integer @property (nonatomic, strong) NSNumber *
#define Float Integer
#define Boolean Integer
#define String @property (nonatomic, strong) NSString *
#define Date @property (nonatomic, strong) NSDate *
#define Array @property (nonatomic, strong) NSArray *
#define ToMany(__className) @property (nonatomic, strong) NSArray<__className> *
#define ToOne(__className) @property (nonatomic, strong) __className *

@interface Property : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) Class type;
@property (nonatomic, strong) NSArray *protocols;

@end


@interface JLModel : NSObject

@property (nonatomic, readonly) NSArray *properties;

- (id)initWithDictionary:(NSDictionary *)keyedValues;
- (void)clear;

@end
