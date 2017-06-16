//
//  MTLModel.m
//  Mantle
//
//  Created by Justin Spahr-Summers on 2012-09-11.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "NSError+MTLModelException.h"
#import "MTLModel.h"
#import <Mantle/EXTRuntimeExtensions.h>
#import <Mantle/EXTScope.h>
#import "MTLReflection.h"
#import <objc/runtime.h>

// Used to cache the reflection performed in +propertyKeys.
static void *MTLModelCachedPropertyKeysKey = &MTLModelCachedPropertyKeysKey;

// Associated in +generateAndCachePropertyKeys with a set of all transitory
// property keys.
static void *MTLModelCachedTransitoryPropertyKeysKey = &MTLModelCachedTransitoryPropertyKeysKey;

// Associated in +generateAndCachePropertyKeys with a set of all permanent
// property keys.
static void *MTLModelCachedPermanentPropertyKeysKey = &MTLModelCachedPermanentPropertyKeysKey;

// Validates a value for an object and sets it if necessary.
//
// obj         - The object for which the value is being validated. This value
//               must not be nil.
// key         - The name of one of `obj`s properties. This value must not be
//               nil.
// value       - The new value for the property identified by `key`.
// forceUpdate - If set to `YES`, the value is being updated even if validating
//               it did not change it.
// error       - If not NULL, this may be set to any error that occurs during
//               validation
//
// Returns YES if `value` could be validated and set, or NO if an error
// occurred.
static BOOL MTLValidateAndSetValue(id obj, NSString *key, id value, BOOL forceUpdate, NSError **error) {
	// Mark this as being autoreleased, because validateValue may return
	// a new object to be stored in this variable (and we don't want ARC to
	// double-free or leak the old or new values).
	__autoreleasing id validatedValue = value;

	@try {
		/// 验证 value 是否有效 , KVC
		if (![obj validateValue:&validatedValue forKey:key error:error]) return NO;

		/// 设置 key 的值为 value, KVC
		if (forceUpdate || value != validatedValue) {
			[obj setValue:validatedValue forKey:key];
		}

		return YES;
	} @catch (NSException *ex) {
		NSLog(@"*** Caught exception setting key \"%@\" : %@", key, ex);

		// Fail fast in Debug builds.
		#if DEBUG
		@throw ex;
		#else
		if (error != NULL) {
			*error = [NSError mtl_modelErrorWithException:ex];
		}

		return NO;
		#endif
	}
}

@interface MTLModel ()

// Inspects all properties of returned by +propertyKeys using
// +storageBehaviorForPropertyWithKey and caches the results.
+ (void)generateAndCacheStorageBehaviors;

// Returns a set of all property keys for which
// +storageBehaviorForPropertyWithKey returned MTLPropertyStorageTransitory.
+ (NSSet *)transitoryPropertyKeys;

// Returns a set of all property keys for which
// +storageBehaviorForPropertyWithKey returned MTLPropertyStoragePermanent.
+ (NSSet *)permanentPropertyKeys;

// Enumerates all properties of the receiver's class hierarchy, starting at the
// receiver, and continuing up until (but not including) MTLModel.
//
// The given block will be invoked multiple times for any properties declared on
// multiple classes in the hierarchy.
+ (void)enumeratePropertiesUsingBlock:(void (^)(objc_property_t property, BOOL *stop))block;

@end

@implementation MTLModel

#pragma mark Lifecycle

+ (void)generateAndCacheStorageBehaviors {
	NSMutableSet *transitoryKeys = [NSMutableSet set];
	NSMutableSet *permanentKeys = [NSMutableSet set];

	/// 1. 遍历所有属性
	for (NSString *propertyKey in self.propertyKeys) {
		/// 2. 根据属性的存储类型，进行分类
		switch ([self storageBehaviorForPropertyWithKey:propertyKey]) {
			case MTLPropertyStorageNone:
				break;

			case MTLPropertyStorageTransitory:
				[transitoryKeys addObject:propertyKey];
				break;

			case MTLPropertyStoragePermanent:
				[permanentKeys addObject:propertyKey];
				break;
		}
	}

	// It doesn't really matter if we replace another thread's work, since we do
	// it atomically and the result should be the same.
	/// 3. 设置关联对象
	objc_setAssociatedObject(self, MTLModelCachedTransitoryPropertyKeysKey, transitoryKeys, OBJC_ASSOCIATION_COPY);
	objc_setAssociatedObject(self, MTLModelCachedPermanentPropertyKeysKey, permanentKeys, OBJC_ASSOCIATION_COPY);
}

+ (instancetype)modelWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
	return [[self alloc] initWithDictionary:dictionary error:error];
}

- (instancetype)init {
	// Nothing special by default, but we have a declaration in the header.
	return [super init];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
	self = [self init];
	if (self == nil) return nil;

	for (NSString *key in dictionary) {
		// Mark this as being autoreleased, because validateValue may return
		// a new object to be stored in this variable (and we don't want ARC to
		// double-free or leak the old or new values).
		/// 将value标记为__autoreleasing，这是因为在MTLValidateAndSetValue函数中，
		///	可以会返回一个新的对象存储在该变量中（我们不希望 ARC 两次释放或者 将旧的或新的对象内存泄露）
		__autoreleasing id value = [dictionary objectForKey:key];

		/// 在JSON 上的值为 nil, 转成 Dictionary 为 NSNull.null, 此时再转成 nil
		if ([value isEqual:NSNull.null]) value = nil;

		/// 通过 KVC 机制验证value 与 key 是否有效，成功时将 self 的属性 key设置值为 value，并返回 yes
		BOOL success = MTLValidateAndSetValue(self, key, value, YES, error);
		/// 如果失败，则返回 nil
		if (!success) return nil;
	}

	return self;
}

#pragma mark Reflection

///  遍历本类及其父类的所有属性
+ (void)enumeratePropertiesUsingBlock:(void (^)(objc_property_t property, BOOL *stop))block {
	Class cls = self;
	BOOL stop = NO;

	/// 1. 设置根类为 MTLModel
	while (!stop && ![cls isEqual:MTLModel.class]) {
		unsigned count = 0;
		/// 2. 获取类的属性
		objc_property_t *properties = class_copyPropertyList(cls, &count);

		/// 3. 获取父类
		cls = cls.superclass;
		if (properties == NULL) continue;

		@onExit {
			free(properties);
		};

		/// 4. 循环遍历，调用 block
		for (unsigned i = 0; i < count; i++) {
			block(properties[i], &stop);
			if (stop) break;
		}
	}
}

+ (NSSet *)propertyKeys {
	/// 1. 关联对象中是否有缓存的keys
	NSSet *cachedKeys = objc_getAssociatedObject(self, MTLModelCachedPropertyKeysKey);
	/// 2. 关联对象不为空，直接返回
	if (cachedKeys != nil) return cachedKeys;

	NSMutableSet *keys = [NSMutableSet set];

	/// 3. 遍历所有属性
	[self enumeratePropertiesUsingBlock:^(objc_property_t property, BOOL *stop) {
		/// 4. 获取属性名字
		NSString *key = @(property_getName(property));

		/// 5. 验证属性的存储类型不为 None.
		if ([self storageBehaviorForPropertyWithKey:key] != MTLPropertyStorageNone) {
			/// 6. 将 key 添加至集合上
			 [keys addObject:key];
		}
	}];

	// It doesn't really matter if we replace another thread's work, since we do
	// it atomically and the result should be the same.
	/// 7. 不在意覆盖了别的线程的数据，所以设置为原子 copy， 并设置关联对象
	objc_setAssociatedObject(self, MTLModelCachedPropertyKeysKey, keys, OBJC_ASSOCIATION_COPY);

	/// 8. 返回keys集合
	return keys;
}

+ (NSSet *)transitoryPropertyKeys {
	NSSet *transitoryPropertyKeys = objc_getAssociatedObject(self, MTLModelCachedTransitoryPropertyKeysKey);

	if (transitoryPropertyKeys == nil) {
		[self generateAndCacheStorageBehaviors];
		transitoryPropertyKeys = objc_getAssociatedObject(self, MTLModelCachedTransitoryPropertyKeysKey);
	}

	return transitoryPropertyKeys;
}

+ (NSSet *)permanentPropertyKeys {
	NSSet *permanentPropertyKeys = objc_getAssociatedObject(self, MTLModelCachedPermanentPropertyKeysKey);

	if (permanentPropertyKeys == nil) {
		[self generateAndCacheStorageBehaviors];
		permanentPropertyKeys = objc_getAssociatedObject(self, MTLModelCachedPermanentPropertyKeysKey);
	}

	return permanentPropertyKeys;
}

- (NSDictionary *)dictionaryValue {
	NSSet *keys = [self.class.transitoryPropertyKeys setByAddingObjectsFromSet:self.class.permanentPropertyKeys];

	return [self dictionaryWithValuesForKeys:keys.allObjects];
}

/// 获取属性名的存储类型
+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey {
	objc_property_t property = class_getProperty(self.class, propertyKey.UTF8String);

	if (property == NULL) return MTLPropertyStorageNone;

	/// 1. 获取属性结构
	mtl_propertyAttributes *attributes = mtl_copyPropertyAttributes(property);
	@onExit {
		free(attributes);
	};

	/// 2. 是否有 getter, setter
	BOOL hasGetter = [self instancesRespondToSelector:attributes->getter];
	BOOL hasSetter = [self instancesRespondToSelector:attributes->setter];

	/// 3. 如果没有 getter, setter, 并且不是 dynamic，也没有相应的成员变量，则为 None.
	if (!attributes->dynamic && attributes->ivar == NULL && !hasGetter && !hasSetter) {
		return MTLPropertyStorageNone;
	} else if (attributes->readonly && attributes->ivar == NULL) {
		/// 只读，并且没有相应的成员变量
		if ([self isEqual:MTLModel.class]) {
			/// 是 MTLModel 根类，则返回 None.
			return MTLPropertyStorageNone;
		} else {
			// Check superclass in case the subclass redeclares a property that
			// falls through
			/// 递归验证父类的存储类型
			return [self.superclass storageBehaviorForPropertyWithKey:propertyKey];
		}
	} else {
		/// 可以序列化
		return MTLPropertyStoragePermanent;
	}
}

#pragma mark Merging

- (void)mergeValueForKey:(NSString *)key fromModel:(NSObject<MTLModel> *)model {
	NSParameterAssert(key != nil);

	/// MTLSelectorWithCapitalizedKeyPattern函数以C语言的方式来拼接方法字符串
	/// 根据传入的key拼接"merge<Key>FromModel:"字符串，并从该字符串中获取到对应的selector
	SEL selector = MTLSelectorWithCapitalizedKeyPattern("merge", key, "FromModel:");
	/// 如果当前对象没有实现-merge<Key>FromModel:方法
	if (![self respondsToSelector:selector]) {
		/// model不为nil，则用model的属性值替代当前对象的属性值
		if (model != nil) {
			[self setValue:[model valueForKey:key] forKey:key];
		}
		return;
	}

	/// 调用自定义的merge<Key>FromModel:方法
	IMP imp = [self methodForSelector:selector];
	void (*function)(id, SEL, id<MTLModel>) = (__typeof__(function))imp;
	function(self, selector, model);
}

- (void)mergeValuesForKeysFromModel:(id<MTLModel>)model {
	NSSet *propertyKeys = model.class.propertyKeys;
	/// 遍历所有属性，并从 model 上 merge 值
	for (NSString *key in self.class.propertyKeys) {
		if (![propertyKeys containsObject:key]) continue;

		[self mergeValueForKey:key fromModel:model];
	}
}

#pragma mark Validation

/// 通过 KVC机制验证所有的属性是否有效
- (BOOL)validate:(NSError **)error {
	for (NSString *key in self.class.propertyKeys) {
		id value = [self valueForKey:key];

		BOOL success = MTLValidateAndSetValue(self, key, value, NO, error);
		if (!success) return NO;
	}

	return YES;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
	MTLModel *copy = [[self.class allocWithZone:zone] init];
	/// 设置所有键值含：permanent 和 transitory类型的键，通过 KVC 设置值。
	[copy setValuesForKeysWithDictionary:self.dictionaryValue];
	return copy;
}

#pragma mark NSObject

- (NSString *)description {
	NSDictionary *permanentProperties = [self dictionaryWithValuesForKeys:self.class.permanentPropertyKeys.allObjects];

	return [NSString stringWithFormat:@"<%@: %p> %@", self.class, self, permanentProperties];
}

- (NSUInteger)hash {
	NSUInteger value = 0;

	/// 通过 序列化键值的 hash 进行异或运算得出新的 hash 值
	for (NSString *key in self.class.permanentPropertyKeys) {
		value ^= [[self valueForKey:key] hash];
	}

	return value;
}

- (BOOL)isEqual:(MTLModel *)model {
	if (self == model) return YES;
	if (![model isMemberOfClass:self.class]) return NO;

	/// 遍历所有的序列化属性
	for (NSString *key in self.class.permanentPropertyKeys) {
		id selfValue = [self valueForKey:key];
		id modelValue = [model valueForKey:key];
		/// 都是 nil，或者值相同，则相同
		BOOL valuesEqual = ((selfValue == nil && modelValue == nil) || [selfValue isEqual:modelValue]);
		if (!valuesEqual) return NO;
	}

	return YES;
}

@end
