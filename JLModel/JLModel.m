//
//  JLModel.m
//  JLModel
//
//  Created by 전수열 on 13. 10. 10..
//  Copyright (c) 2013년 MyFoodList. All rights reserved.
//

#import "JLModel.h"
#import <objc/runtime.h>

@implementation Property

- (NSString *)description
{
    if (self.protocols) {
        NSMutableString *protocolDescription = [NSMutableString stringWithString:@"<"];
        for (NSString *protocol in self.protocols) {
            [protocolDescription appendString:protocol];
            if (self.protocols.lastObject != protocol) {
                [protocolDescription appendString:@", "];
            }
        }
        [protocolDescription appendString:@">"];
        return [NSString stringWithFormat:@"<Property: %@%@ *%@>", self.type, protocolDescription, self.name];
    }

    return [NSString stringWithFormat:@"<Property: %@ *%@>", self.type, self.name];
}

@end


@implementation JLModel


#pragma mark -
#pragma mark Flyweight

/**
 * Returns model dictionary for this class.
 */
+ (NSMutableDictionary *)models
{
    static NSMutableDictionary *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [NSMutableDictionary dictionary];
    });

    NSNumber *hash = [NSNumber numberWithUnsignedLong:[self class].hash];
    NSMutableDictionary *models = store[hash];
    if (!models) {
        models = [NSMutableDictionary dictionary];
        store[hash] = models;
    }
    return models;
}

+ (id)modelWithID:(id)id
{
    // create and return new instance if model has no id
    if (!id) {
        return [[[self class] alloc] init];
    }

    NSMutableDictionary *models = [[self class] models];
    JLModel *model = models[id];
    if (!model) {
        NSLog(@"Create: <%@:%@>", [self class].description, id);
        model = [[[self class] alloc] init];
        models[id] = model;
    } else {
        NSLog(@"Reuse: <%@:%@>", [self class].description, id);
    }
    return model;
}

+ (id)modelWithDictionary:(NSDictionary *)dictionary
{
    id id = dictionary[@"id"];
    JLModel *model = [[self class] modelWithID:id];
    [model setValuesForKeysWithDictionary:dictionary];
    return model;
}

+ (void)delete:(JLModel *)model
{
    [[[self class] models] removeObjectForKey:model.id];
}


#pragma mark -
#pragma mark Constructor

- (id)initWithDictionary:(NSDictionary *)keyedValues
{
    self = [super init];
    [self setValuesForKeysWithDictionary:keyedValues];
    return self;
}


#pragma mark -

- (void)setValuesForKeysWithDictionary:(NSDictionary *)keyedValues
{
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    NSArray *properties = self.properties;
    for (Property *property in properties)
    {
        if (property.readonly) {
            continue;
        }

        id value = [keyedValues objectForKey:property.name];

        if (!value || [value isEqual:[NSNull null]]) {
            // use default value for array if existing value is nil.
            if ([property.type isSubclassOfClass:[NSArray class]] && ![self valueForKey:property.name]) {
                value = [[property.type alloc] init];
            } else {
                continue;
            }
        }

        else if (property.type == NSString.class && [value isKindOfClass:NSNumber.class]) {
            value = [value stringValue];
        }

        else if (property.type == NSNumber.class && [value isKindOfClass:NSString.class]) {
            value = [numberFormatter numberFromString:value];
        }

        else if (property.type == NSDate.class) {
            value = [self parseDateString:value forField:property.name];
        }

        // ToOne
        else if ([property.type isSubclassOfClass:JLModel.class]) {
            value = [property.type modelWithDictionary:value];
        }

        // ToMany
        else if ([property.type isSubclassOfClass:[NSArray class]])
        {
            // no model type definition
            if (![value count]) {
                value = [NSMutableArray array];
            }

            Class elementClass = nil;
            for (NSString *protocol in property.protocols) {
                Class protocolClass = NSClassFromString(protocol);
                if ([protocolClass isSubclassOfClass:JLModel.class]) {
                    elementClass = protocolClass;
                    break;
                }
            }

            if (!elementClass) {
                value = value;
            } else {
                NSMutableArray *elements = [NSMutableArray array];
                for (NSDictionary *dict in value) {
                    JLModel *elem = [elementClass modelWithDictionary:dict];
                    [elements addObject:elem];
                }
                value = elements;
            }
        }

        [self setValue:value forKey:property.name];
    }
}

- (void)clear
{
    NSArray *properties = self.properties;
    for (Property *property in properties)
    {
        [self setValue:nil forKey:property.name];
    }
}

/**
 * Returns all properties.
 */
- (NSArray *)properties
{
    NSMutableArray *properties = [[NSMutableArray alloc] init];
    unsigned int propertyCount = 0;
    objc_property_t *propertyList = class_copyPropertyList(self.class, &propertyCount);

    for (int i = 0; i < propertyCount; i++) {
        objc_property_t property = propertyList[i];

        NSString *type = nil;
        unsigned int attrCount = 0;
        objc_property_attribute_t *attrs = property_copyAttributeList(property, &attrCount);
        for (int j = 0; j < attrCount; j++) {
            objc_property_attribute_t attr = attrs[j];
            if (!strcmp(attr.name, "T")) {
                // e.g. @"NSString", @"NSNumber", @"NSMutableArray<User>"(ToMany), @"User"(ToOne)
                type = [NSString stringWithUTF8String:attr.value];
                break;
            }
        }

        Property *p = [[Property alloc] init];
        p.name = [NSString stringWithUTF8String:property_getName(property)];

        const char *propertyAttributes = property_getAttributes(property);
        NSArray *attributes = [[NSString stringWithUTF8String:propertyAttributes] componentsSeparatedByString:@","];
        if ([attributes containsObject:@"R"]) {
            p.readonly = YES;
        }

        if ([type isEqualToString:@"@"]) {
            p.type = nil;
        } else {
            if ([type rangeOfString:@"@"].location == NSNotFound) {
                continue;
            }
            NSString *classString = nil;
            NSInteger length = [type rangeOfString:@"<"].location;
            if (length == NSNotFound) {
                length = type.length - 1;
            }
            classString = [type substringWithRange:NSMakeRange(2, length - 2)];
            p.type = NSClassFromString(classString);
        }

        // detect relation model type from protocol
        NSCharacterSet *charSet = [NSCharacterSet characterSetWithCharactersInString:@"<>"];
        NSArray *components = [type componentsSeparatedByCharactersInSet:charSet];
        NSMutableArray *protocols = nil;
        for (NSInteger j = 1; j < components.count - 1; j++) {
            NSString *component = [components objectAtIndex:j];
            if (component.length) {
                if (!protocols) {
                    protocols = [NSMutableArray array];
                }
                [protocols addObject:component];
            }
        }

        p.protocols = protocols;
        [properties addObject:p];
    }

    return properties;
}


#pragma mark -
#pragma mark Abstract

- (NSDate *)parseDateString:(NSString *)dateString forField:(NSString *)field
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd' 'HH:mm:ss";
    dateFormatter.timeZone = [NSTimeZone localTimeZone];
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    return [dateFormatter dateFromString:dateString];
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[JLModel class]]) {
        return [self.id isEqual:[(JLModel *)object id]];
    }
    return [super isEqual:object];
}

- (id)copy
{
    JLModel *newObj = [[[self class] alloc] init];
    for (Property *property in self.properties) {
        if (property.readonly) {
            continue;
        }
        id value = [[self valueForKey:property.name] copy];
        NSLog(@"copy: %@=%@", property.name, value);
        [newObj setValue:value forKey:property.name];
    }
    return newObj;
}

@end
