//
//  EXTRuntimeExtensions.h
//  extobjc
//
//  Created by Justin Spahr-Summers on 2011-03-05.
//  Copyright (C) 2012 Justin Spahr-Summers.
//  Released under the MIT license.
//

#import <objc/runtime.h>

/**
 * Describes the memory management policy of a property.
 * 属性的内存管理策略类型
 */
typedef enum {
    /**
     * The value is assigned.
     */
    mtl_propertyMemoryManagementPolicyAssign = 0,

    /**
     * The value is retained.
     */
    mtl_propertyMemoryManagementPolicyRetain,

    /**
     * The value is copied.
     */
    mtl_propertyMemoryManagementPolicyCopy
} mtl_propertyMemoryManagementPolicy;

/**
 * Describes the attributes and type information of a property.
 * 描述属性的参数和类型信息
 */
typedef struct {
    /**
     * Whether this property was declared with the \c readonly attribute.
	 * 只读
     */
    BOOL readonly;

    /**
     * Whether this property was declared with the \c nonatomic attribute.
	 * 非原子的
     */
    BOOL nonatomic;

    /**
     * Whether the property is a weak reference.
	 * 弱引用
     */
    BOOL weak;

    /**
     * Whether the property is eligible for garbage collection.
	 * 使用 GC
     */
    BOOL canBeCollected;

    /**
     * Whether this property is defined with \c \@dynamic.
	 * 动态属性
     */
    BOOL dynamic;

    /**
     * The memory management policy for this property. This will always be
     * #mtl_propertyMemoryManagementPolicyAssign if #readonly is \c YES.
	 * 如果为只读，则属性内存管理策略为 assign
     */
    mtl_propertyMemoryManagementPolicy memoryManagementPolicy;

    /**
     * The selector for the getter of this property. This will reflect any
     * custom \c getter= attribute provided in the property declaration, or the
     * inferred getter name otherwise.
     */
    SEL getter;

    /**
     * The selector for the setter of this property. This will reflect any
     * custom \c setter= attribute provided in the property declaration, or the
     * inferred setter name otherwise.
     *
     * @note If #readonly is \c YES, this value will represent what the setter
     * \e would be, if the property were writable.
     */
    SEL setter;

    /**
     * The backing instance variable for this property, or \c NULL if \c
     * \c @synthesize was not used, and therefore no instance variable exists. This
     * would also be the case if the property is implemented dynamically.
	 * 属性对应的成员变量
     */
    const char *ivar;

    /**
     * If this property is defined as being an instance of a specific class,
     * this will be the class object representing it.
     *
     * This will be \c nil if the property was defined as type \c id, if the
     * property is not of an object type, or if the class could not be found at
     * runtime.
	 * 属性的类 类型
     */
    Class objectClass;

    /**
     * The type encoding for the value of this property. This is the type as it
     * would be returned by the \c \@encode() directive.
	 * encode Typeing
     */
    char type[];
} mtl_propertyAttributes;

/**
 * Returns a pointer to a structure containing information about \a property.
 * You must \c free() the returned pointer. Returns \c NULL if there is an error
 * obtaining information from \a property.
 */
/// 返回结构，包括属性的信息。需要手动调用 free()释放返回的内存
mtl_propertyAttributes *mtl_copyPropertyAttributes (objc_property_t property);
