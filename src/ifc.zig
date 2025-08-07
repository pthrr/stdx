const std = @import("std");

// Interface System - All Available Method Modifiers:
//
// 1. Regular method (required, exact type match):
//    .method = fn (*Self) ReturnType
//    Use for: Methods that must exist with exact signature (including Self substitution)
//
// 2. Optional method (can be missing):
//    .method = Optional(fn (*Self) ReturnType)
//    Use for: Methods that may or may not be implemented
//
// 3. Constrained method (required, parameter/return types must match constraint):
//    .method = Constraint(fn (*Self, TypeConstraints.Numeric) TypeConstraints.Numeric)
//    Use for: Methods where you want flexible numeric types, not for Self substitution
//    DON'T use for: Self return types (use regular function signature instead)
//
// 4. Optional with default (can be missing, has default impl):
//    .method = OptionalDefault(fn (*Self) ReturnType, defaultImpl)
//    Use for: Optional methods with fallback behavior
//
// 5. Optional with constraint (can be missing, types must match constraint):
//    .method = OptionalConstraint(fn (*Self) TypeConstraints.Numeric)
//    Use for: Optional methods with flexible type requirements
//
// 6. Optional with constraint and default (all three features):
//    .method = OptionalConstraintDefault(fn (*Self) TypeConstraints.Numeric, defaultImpl)
//    Use for: Maximum flexibility - optional, type-flexible, with fallback

/// Property-based type constraint system that can inspect any type
pub const TypeConstraints = struct {
    /// Check if type has a specific field
    pub fn HasField(comptime field_name: []const u8) type {
        return struct {
            pub fn matches(comptime T: type) bool {
                return @hasField(T, field_name);
            }

            pub fn description() []const u8 {
                return "type with field '" ++ field_name ++ "'";
            }
        };
    }

    /// Check if type has a specific method
    pub fn HasMethod(comptime method_name: []const u8) type {
        return struct {
            pub fn matches(comptime T: type) bool {
                return @hasDecl(T, method_name);
            }

            pub fn description() []const u8 {
                return "type with method '" ++ method_name ++ "'";
            }
        };
    }

    /// Check if type is exactly a specific type
    pub fn Exact(comptime TargetType: type) type {
        return struct {
            pub fn matches(comptime T: type) bool {
                return T == TargetType;
            }

            pub fn description() []const u8 {
                return "exactly type " ++ @typeName(TargetType);
            }
        };
    }

    /// Combine multiple constraints with AND logic
    pub fn AllOf(comptime constraints: anytype) type {
        return struct {
            pub fn matches(comptime T: type) bool {
                inline for (constraints) |constraint| {
                    if (!constraint.matches(T)) return false;
                }
                return true;
            }

            pub fn description() []const u8 {
                return "type satisfying all constraints";
            }
        };
    }

    /// Combine multiple constraints with OR logic
    pub fn AnyOf(comptime constraints: anytype) type {
        return struct {
            pub fn matches(comptime T: type) bool {
                inline for (constraints) |constraint| {
                    if (constraint.matches(T)) return true;
                }
                return false;
            }

            pub fn description() []const u8 {
                return "type satisfying any constraint";
            }
        };
    }

    /// Check type category (Int, Float, Struct, etc.)
    pub fn OfCategory(comptime category: std.builtin.TypeId) type {
        return struct {
            pub fn matches(comptime T: type) bool {
                return @typeInfo(T) == category;
            }

            pub fn description() []const u8 {
                return "type of category " ++ @tagName(category);
            }
        };
    }

    /// Helper to create constraints for specific type sets
    pub fn OneOf(comptime types: anytype) type {
        comptime var constraints: [types.len]type = undefined;
        inline for (types, 0..) |T, i| {
            constraints[i] = Exact(T);
        }
        return AnyOf(constraints);
    }

    /// Primitive type constraint library
    pub const PrimitiveTypes = struct {
        pub const Ints = OneOf(.{ i8, i16, i32, i64, i128, isize, u8, u16, u32, u64, u128, usize });
        pub const Floats = OneOf(.{ f16, f32, f64, f80, f128 });
        pub const Numeric = AnyOf(.{ Ints, Floats });
        pub const Signed = OneOf(.{ i8, i16, i32, i64, i128, isize });
        pub const Unsigned = OneOf(.{ u8, u16, u32, u64, u128, usize });
        pub const CounterTypes = OneOf(.{ u8, u16, u32, u64, usize });
        pub const IndexTypes = OneOf(.{ usize, u32, u16 });
    };

    pub const Integral = OfCategory(.int);
    pub const Float = OfCategory(.float);
    pub const Struct = OfCategory(.@"struct");
    pub const Numeric = PrimitiveTypes.Numeric;
};

/// Wraps a type constraint for use in interface method signatures
pub fn Constraint(comptime constraint: anytype) type {
    return struct {
        pub const type_constraint = constraint;
        pub const is_constraint = true;
    };
}

/// Marks a method as optional in interface definitions
pub fn Optional(comptime method_type: anytype) type {
    return struct {
        pub const signature = method_type;
        pub const is_optional = true;
    };
}

/// Marks a method as optional with a default implementation
pub fn OptionalDefault(comptime method_signature: anytype, comptime default_impl: anytype) type {
    return struct {
        pub const signature = method_signature;
        pub const default = default_impl;
        pub const is_optional = true;
        pub const has_default = true;
    };
}

/// Helper for optional methods with constraints
pub fn OptionalConstraint(comptime constraint: anytype) type {
    return struct {
        pub const type_constraint = constraint;
        pub const is_optional = true;
        pub const is_constraint = true;
    };
}

/// Helper for optional methods with constraints and default implementation
pub fn OptionalConstraintDefault(comptime constraint: anytype, comptime default_impl: anytype) type {
    return struct {
        pub const type_constraint = constraint;
        pub const default = default_impl;
        pub const is_optional = true;
        pub const is_constraint = true;
        pub const has_default = true;
    };
}

/// Special marker type for self parameter in interface definitions
const Self = struct {
    // Unique marker type for Self references in interfaces
};

/// Check if two function signatures match, handling Self marker type
fn signatureMatches(comptime expected_fn: anytype, comptime actual_type: type, comptime implementing_type: type) bool {
    const actual_info = @typeInfo(actual_type);
    if (actual_info != .@"fn") return false;

    // Get expected function info
    const expected_type = @TypeOf(expected_fn);
    const expected_info = if (@typeInfo(expected_type) == .type)
        @typeInfo(expected_fn)
    else
        @typeInfo(expected_type);

    if (expected_info != .@"fn") return false;

    const actual_fn = actual_info.@"fn";
    const expected_fn_info = expected_info.@"fn";

    // Check parameter count
    if (actual_fn.params.len != expected_fn_info.params.len) return false;

    // Check each parameter
    inline for (actual_fn.params, expected_fn_info.params) |actual_param, expected_param| {
        if (actual_param.type == null or expected_param.type == null) continue;

        const expected_type_param = expected_param.type.?;
        const actual_type_param = actual_param.type.?;

        // Handle *Self -> *ImplementingType mapping (including const pointers)
        if (@typeInfo(expected_type_param) == .pointer) {
            const expected_ptr = @typeInfo(expected_type_param).pointer;
            if (expected_ptr.child == Self) {
                if (@typeInfo(actual_type_param) == .pointer) {
                    const actual_ptr = @typeInfo(actual_type_param).pointer;
                    if (actual_ptr.child == implementing_type and
                        expected_ptr.is_const == actual_ptr.is_const)
                    {
                        continue;
                    }
                }
                return false;
            }
        }

        // Handle Self -> ImplementingType mapping
        if (expected_type_param == Self) {
            if (actual_type_param == implementing_type) {
                continue;
            }
            return false;
        }

        // Otherwise require exact match
        if (actual_type_param != expected_type_param) return false;
    }

    // Check return types (including pointer return types)
    if (actual_fn.return_type != expected_fn_info.return_type) {
        if (actual_fn.return_type == null or expected_fn_info.return_type == null) {
            return actual_fn.return_type == expected_fn_info.return_type;
        }

        const expected_return = expected_fn_info.return_type.?;
        const actual_return = actual_fn.return_type.?;

        // Handle Self -> ImplementingType mapping for return types
        if (expected_return == Self) {
            return actual_return == implementing_type;
        }

        // Handle *Self -> *ImplementingType mapping for return types
        if (@typeInfo(expected_return) == .pointer) {
            const expected_ptr = @typeInfo(expected_return).pointer;
            if (expected_ptr.child == Self) {
                if (@typeInfo(actual_return) == .pointer) {
                    const actual_ptr = @typeInfo(actual_return).pointer;
                    if (actual_ptr.child == implementing_type and
                        expected_ptr.is_const == actual_ptr.is_const)
                    {
                        return true;
                    }
                }
                return false;
            }
        }

        // Handle error union types with Self
        if (@typeInfo(expected_return) == .error_union and @typeInfo(actual_return) == .error_union) {
            const expected_eu = @typeInfo(expected_return).error_union;
            const actual_eu = @typeInfo(actual_return).error_union;

            // Check error set matches - both null (anyerror) or same error set
            if (expected_eu.error_set != actual_eu.error_set) {
                return false;
            }

            // Check payload with Self substitution
            const expected_payload = expected_eu.payload;
            const actual_payload = actual_eu.payload;

            // Direct Self substitution - use proper type comparison
            if (expected_payload == Self and actual_payload == implementing_type) {
                return true;
            }

            // Handle *Self in error union payload
            if (@typeInfo(expected_payload) == .pointer) {
                const expected_ptr = @typeInfo(expected_payload).pointer;
                if (expected_ptr.child == Self) {
                    if (@typeInfo(actual_payload) == .pointer) {
                        const actual_ptr = @typeInfo(actual_payload).pointer;
                        if (actual_ptr.child == implementing_type and
                            expected_ptr.is_const == actual_ptr.is_const)
                        {
                            return true;
                        }
                    }
                    return false;
                }
            }

            // Otherwise payloads must match exactly
            return expected_payload == actual_payload;
        }

        // Handle optional types with Self
        if (@typeInfo(expected_return) == .optional and @typeInfo(actual_return) == .optional) {
            const expected_child = @typeInfo(expected_return).optional.child;
            const actual_child = @typeInfo(actual_return).optional.child;

            if (expected_child == Self) {
                return actual_child == implementing_type;
            }

            // Handle *Self in optional
            if (@typeInfo(expected_child) == .pointer) {
                const expected_ptr = @typeInfo(expected_child).pointer;
                if (expected_ptr.child == Self) {
                    if (@typeInfo(actual_child) == .pointer) {
                        const actual_ptr = @typeInfo(actual_child).pointer;
                        if (actual_ptr.child == implementing_type and
                            expected_ptr.is_const == actual_ptr.is_const)
                        {
                            return true;
                        }
                    }
                    return false;
                }
            }

            return expected_child == actual_child;
        }

        // Otherwise require exact match
        if (actual_return != expected_return) return false;
    }

    return true;
}

/// Check if a function type matches constraint pattern
fn matchesFunctionConstraint(comptime constraint: anytype, comptime actual_fn_type: type, comptime implementing_type: type) bool {
    const actual_info = @typeInfo(actual_fn_type);
    if (actual_info != .@"fn") return false;

    const constraint_info = @typeInfo(constraint);
    if (constraint_info != .@"fn") return false;

    const actual_fn = actual_info.@"fn";
    const constraint_fn = constraint_info.@"fn";

    // Check parameter count
    if (actual_fn.params.len != constraint_fn.params.len) return false;

    // Check each parameter
    inline for (actual_fn.params, constraint_fn.params) |actual_param, constraint_param| {
        if (actual_param.type == null or constraint_param.type == null) continue;

        const expected_type_orig = constraint_param.type.?;
        const actual_type = actual_param.type.?;

        // Handle Self substitution first
        const expected_type = if (@typeInfo(expected_type_orig) == .pointer) blk: {
            const expected_ptr = @typeInfo(expected_type_orig).pointer;
            if (expected_ptr.child == Self) {
                // Preserve const qualifier when substituting Self
                if (expected_ptr.is_const) {
                    break :blk *const implementing_type;
                } else {
                    break :blk *implementing_type;
                }
            } else {
                break :blk expected_type_orig;
            }
        } else if (expected_type_orig == Self) blk: {
            break :blk implementing_type;
        } else blk: {
            break :blk expected_type_orig;
        };

        // After Self substitution, check if the original (non-Self) type is a constraint
        // Only check for constraints on non-pointer, non-Self types
        if (expected_type_orig != Self and
            @typeInfo(expected_type_orig) != .pointer and
            @typeInfo(@TypeOf(expected_type_orig)) == .type)
        {
            const orig_info = @typeInfo(expected_type_orig);
            if (orig_info == .@"struct" and @hasDecl(expected_type_orig, "matches")) {
                if (!expected_type_orig.matches(actual_type)) {
                    return false;
                }
                continue;
            }
        }

        // Regular type matching
        if (actual_type != expected_type) return false;
    }

    // Check return type
    if (actual_fn.return_type != constraint_fn.return_type) {
        if (actual_fn.return_type == null or constraint_fn.return_type == null) {
            return actual_fn.return_type == constraint_fn.return_type;
        }

        const expected_return_orig = constraint_fn.return_type.?;
        const actual_return = actual_fn.return_type.?;

        // Handle error union types with Self or constraints
        if (@typeInfo(expected_return_orig) == .error_union and @typeInfo(actual_return) == .error_union) {
            const expected_eu = @typeInfo(expected_return_orig).error_union;
            const actual_eu = @typeInfo(actual_return).error_union;

            // Check error set matches - both null (anyerror) or same error set
            if (expected_eu.error_set != actual_eu.error_set) {
                return false;
            }

            // Check payload with Self substitution or constraint matching
            const payload_orig = expected_eu.payload;
            const actual_payload = actual_eu.payload;

            // Handle Self in error union payload
            if (payload_orig == Self) {
                return actual_payload == implementing_type;
            }

            // Handle *Self in error union payload
            if (@typeInfo(payload_orig) == .pointer) {
                const expected_ptr = @typeInfo(payload_orig).pointer;
                if (expected_ptr.child == Self) {
                    if (@typeInfo(actual_payload) == .pointer) {
                        const actual_ptr = @typeInfo(actual_payload).pointer;
                        if (actual_ptr.child == implementing_type and
                            expected_ptr.is_const == actual_ptr.is_const)
                        {
                            return true;
                        }
                    }
                    return false;
                }
            }

            // Check if payload is a constraint
            if (@typeInfo(@TypeOf(payload_orig)) == .type) {
                const orig_info = @typeInfo(payload_orig);
                if (orig_info == .@"struct" and @hasDecl(payload_orig, "matches")) {
                    return payload_orig.matches(actual_payload);
                }
            }

            // Otherwise payloads must match exactly
            return payload_orig == actual_payload;
        }

        // Handle optional types with Self or constraints
        if (@typeInfo(expected_return_orig) == .optional and @typeInfo(actual_return) == .optional) {
            const expected_child = @typeInfo(expected_return_orig).optional.child;
            const actual_child = @typeInfo(actual_return).optional.child;

            // Handle Self in optional
            if (expected_child == Self) {
                return actual_child == implementing_type;
            }

            // Handle *Self in optional
            if (@typeInfo(expected_child) == .pointer) {
                const expected_ptr = @typeInfo(expected_child).pointer;
                if (expected_ptr.child == Self) {
                    if (@typeInfo(actual_child) == .pointer) {
                        const actual_ptr = @typeInfo(actual_child).pointer;
                        if (actual_ptr.child == implementing_type and
                            expected_ptr.is_const == actual_ptr.is_const)
                        {
                            return true;
                        }
                    }
                    return false;
                }
            }

            // Check if child is a constraint
            if (@typeInfo(@TypeOf(expected_child)) == .type) {
                const child_info = @typeInfo(expected_child);
                if (child_info == .@"struct" and @hasDecl(expected_child, "matches")) {
                    return expected_child.matches(actual_child);
                }
            }

            return expected_child == actual_child;
        }

        // Check if the return type is a constraint (struct with matches method)
        if (expected_return_orig != Self and
            @typeInfo(@TypeOf(expected_return_orig)) == .type)
        {
            const orig_info = @typeInfo(expected_return_orig);
            if (orig_info == .@"struct" and @hasDecl(expected_return_orig, "matches")) {
                if (!expected_return_orig.matches(actual_return)) {
                    return false;
                }
            } else {
                // Handle Self substitution for non-constraint return types
                const expected_return = if (expected_return_orig == Self)
                    implementing_type
                else
                    expected_return_orig;

                if (actual_return != expected_return) {
                    return false;
                }
            }
        } else {
            // Handle Self substitution
            const expected_return = if (expected_return_orig == Self)
                implementing_type
            else
                expected_return_orig;

            if (actual_return != expected_return) {
                return false;
            }
        }
    }

    return true;
}

/// Creates a compile-time interface checker from method signatures
pub fn Interface(comptime methods: anytype) type {
    return struct {
        /// Check if type T implements this interface (returns bool)
        pub fn check(comptime T: type) bool {
            inline for (@typeInfo(@TypeOf(methods)).@"struct".fields) |field| {
                const method_name = field.name;
                const method_spec = @field(methods, method_name);

                // Determine method properties
                const is_optional = comptime blk: {
                    if (@typeInfo(@TypeOf(method_spec)) == .type) {
                        const spec_info = @typeInfo(method_spec);
                        if (spec_info == .@"struct" and @hasDecl(method_spec, "is_optional")) {
                            break :blk method_spec.is_optional;
                        }
                    }
                    break :blk false;
                };

                const is_constraint = comptime blk: {
                    if (@typeInfo(@TypeOf(method_spec)) == .type) {
                        const spec_info = @typeInfo(method_spec);
                        if (spec_info == .@"struct" and @hasDecl(method_spec, "is_constraint")) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };

                const has_default = comptime blk: {
                    if (@typeInfo(@TypeOf(method_spec)) == .type) {
                        const spec_info = @typeInfo(method_spec);
                        if (spec_info == .@"struct" and @hasDecl(method_spec, "has_default")) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };

                // Check if type has the method
                if (!@hasDecl(T, method_name)) {
                    if (!is_optional) return false;
                    // Method is optional, so missing is OK
                    continue;
                }

                // Get the actual method type (use @field for fields, but methods are decls)
                const actual_method = @field(T, method_name);
                const actual_type = @TypeOf(actual_method);

                // Validate method signature based on specification type
                const validation_result = if (is_constraint and is_optional and has_default) blk: {
                    // Handle optional constraint with default
                    const constraint = method_spec.type_constraint;
                    break :blk matchesFunctionConstraint(constraint, actual_type, T);
                } else if (is_constraint and is_optional) blk: {
                    // Handle optional constraint
                    const constraint = method_spec.type_constraint;
                    break :blk matchesFunctionConstraint(constraint, actual_type, T);
                } else if (is_constraint) blk: {
                    // Handle regular constraint
                    const constraint = method_spec.type_constraint;
                    break :blk matchesFunctionConstraint(constraint, actual_type, T);
                } else if (has_default) blk: {
                    // Handle optional with default
                    const sig = method_spec.signature;
                    break :blk signatureMatches(sig, actual_type, T);
                } else if (is_optional) blk: {
                    // Handle regular optional
                    const sig = method_spec.signature;
                    if (@typeInfo(sig) == .@"fn") {
                        break :blk signatureMatches(sig, actual_type, T);
                    } else {
                        break :blk actual_type == sig;
                    }
                } else if (@typeInfo(@TypeOf(method_spec)) == .type) blk: {
                    const spec_info = @typeInfo(method_spec);
                    if (spec_info == .@"fn") {
                        // Direct function type
                        break :blk signatureMatches(method_spec, actual_type, T);
                    } else {
                        break :blk actual_type == method_spec;
                    }
                } else blk: {
                    break :blk actual_type == method_spec;
                };

                if (!validation_result) return false;
            }
            return true;
        }

        /// Assert that type T implements this interface (compile error if not)
        pub fn assert(comptime T: type) void {
            if (!check(T)) {
                @compileError("Type '" ++ @typeName(T) ++ "' does not implement interface");
            }
        }
    };
}

// Example types
const Rectangle = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 10,
    height: f32 = 10,

    pub fn getX(self: *@This()) f32 {
        return self.x;
    }
    pub fn getY(self: *@This()) f32 {
        return self.y;
    }
    pub fn setPosition(self: *@This(), x: f64, y: i32) void {
        self.x = @floatCast(x);
        self.y = @floatFromInt(y);
    }
    pub fn draw(self: *@This()) void {
        std.debug.print("Rectangle at ({d}, {d})\n", .{ self.x, self.y });
    }
    pub fn getBounds(self: *@This()) [4]f32 {
        return [_]f32{ self.x, self.y, self.width, self.height };
    }
    pub fn setVisible(self: *@This(), visible: bool) void {
        _ = self;
        _ = visible;
    }
};

// Example interfaces
const Drawable = Interface(.{
    .draw = fn (*Self) void,
    .getBounds = Optional(fn (*Self) [4]f32),
    .setVisible = Optional(fn (*Self, bool) void),
});

const Positionable = Interface(.{
    .getX = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Numeric),
    .getY = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Numeric),
    .setPosition = Constraint(fn (*Self, TypeConstraints.PrimitiveTypes.Numeric, TypeConstraints.PrimitiveTypes.Numeric) void),
});

// Tests
test "basic type constraints" {
    const IntConstraint = TypeConstraints.Exact(i32);
    try std.testing.expect(IntConstraint.matches(i32));
    try std.testing.expect(!IntConstraint.matches(i64));
}

test "numeric constraints" {
    const PT = TypeConstraints.PrimitiveTypes;
    try std.testing.expect(PT.Numeric.matches(f32));
    try std.testing.expect(PT.Numeric.matches(i32));
    try std.testing.expect(!PT.Numeric.matches(bool));
}

test "simple interface validation" {
    const SimpleInterface = Interface(.{
        .getValue = fn (*Self) i32,
    });

    const SimpleStruct = struct {
        pub fn getValue(self: *@This()) i32 {
            _ = self;
            return 42;
        }
    };

    try std.testing.expect(SimpleInterface.check(SimpleStruct));
}

test "drawable interface" {
    try std.testing.expect(Drawable.check(Rectangle));
}

test "positionable interface" {
    try std.testing.expect(Positionable.check(Rectangle));
}

test "constraint-based interface" {
    const TestInterface = Interface(.{
        .getNumeric = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Numeric),
    });

    const TestStruct = struct {
        pub fn getNumeric(self: *@This()) f32 {
            _ = self;
            return 3.14;
        }
    };

    try std.testing.expect(TestInterface.check(TestStruct));
}

test "optional methods" {
    const OptionalInterface = Interface(.{
        .required = fn (*Self) void,
        .optional = Optional(fn (*Self) i32),
    });

    const WithOptional = struct {
        pub fn required(self: *@This()) void {
            _ = self;
        }
        pub fn optional(self: *@This()) i32 {
            _ = self;
            return 42;
        }
    };

    const WithoutOptional = struct {
        pub fn required(self: *@This()) void {
            _ = self;
        }
    };

    try std.testing.expect(OptionalInterface.check(WithOptional));
    try std.testing.expect(OptionalInterface.check(WithoutOptional));
}

test "complex constraint combinations" {
    const ComplexInterface = Interface(.{
        .getFloat = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Floats),
        .getInt = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Ints),
        .process = Constraint(fn (*Self, TypeConstraints.PrimitiveTypes.Numeric) void),
        .optional_method = Optional(fn (*Self) bool),
    });

    const ComplexStruct = struct {
        pub fn getFloat(self: *@This()) f64 {
            _ = self;
            return 3.14;
        }
        pub fn getInt(self: *@This()) i32 {
            _ = self;
            return 42;
        }
        pub fn process(self: *@This(), value: f32) void {
            _ = self;
            _ = value;
        }
        // optional_method not implemented - should still pass
    };

    try std.testing.expect(ComplexInterface.check(ComplexStruct));
}

test "interface validation failure cases" {
    const StrictInterface = Interface(.{
        .requiredMethod = fn (*Self) i32,
        .specificType = Constraint(fn (*Self) TypeConstraints.Exact(f64)),
    });

    const IncompleteStruct = struct {
        // Missing requiredMethod
        pub fn specificType(self: *@This()) f64 {
            _ = self;
            return 3.14;
        }
    };

    const WrongTypeStruct = struct {
        pub fn requiredMethod(self: *@This()) i32 {
            _ = self;
            return 42;
        }
        pub fn specificType(self: *@This()) f32 { // Wrong type - should be f64
            _ = self;
            return 3.14;
        }
    };

    try std.testing.expect(!StrictInterface.check(IncompleteStruct));
    try std.testing.expect(!StrictInterface.check(WrongTypeStruct));
}

test "self substitution variations" {
    const SelfSubInterface = Interface(.{
        .returnsPointerToSelf = fn (*Self) *Self,
        .takesPointerToSelf = fn (*Self) void,
        .takesConstPointerToSelf = fn (*const Self) void,
    });

    const SelfStruct = struct {
        pub fn returnsPointerToSelf(self: *@This()) *@This() {
            return self;
        }
        pub fn takesPointerToSelf(self: *@This()) void {
            _ = self;
        }
        pub fn takesConstPointerToSelf(self: *const @This()) void {
            _ = self;
        }
    };

    try std.testing.expect(SelfSubInterface.check(SelfStruct));
}

test "combined interfaces" {
    // Rectangle should implement both Drawable and Positionable
    const CombinedInterface = Interface(.{
        // From Drawable
        .draw = fn (*Self) void,
        .getBounds = Optional(fn (*Self) [4]f32),
        // From Positionable
        .getX = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Numeric),
        .getY = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Numeric),
    });

    try std.testing.expect(CombinedInterface.check(Rectangle));
}

test "optional with default implementation" {
    const DefaultInterface = Interface(.{
        .getName = OptionalDefault(fn (*Self) []const u8, struct {
            fn default(self: anytype) []const u8 {
                _ = self;
                return "unnamed";
            }
        }.default),
        .getId = fn (*Self) u32,
    });

    const WithName = struct {
        pub fn getName(self: *@This()) []const u8 {
            _ = self;
            return "custom name";
        }
        pub fn getId(self: *@This()) u32 {
            _ = self;
            return 123;
        }
    };

    const WithoutName = struct {
        pub fn getId(self: *@This()) u32 {
            _ = self;
            return 456;
        }
    };

    try std.testing.expect(DefaultInterface.check(WithName));
    try std.testing.expect(DefaultInterface.check(WithoutName));
}

test "optional constraint" {
    const OptConstraintInterface = Interface(.{
        .getValue = OptionalConstraint(fn (*Self) TypeConstraints.PrimitiveTypes.Ints),
        .process = fn (*Self) void,
    });

    const WithGetValue = struct {
        pub fn getValue(self: *@This()) i64 {
            _ = self;
            return 42;
        }
        pub fn process(self: *@This()) void {
            _ = self;
        }
    };

    const WithoutGetValue = struct {
        pub fn process(self: *@This()) void {
            _ = self;
        }
    };

    const WrongReturnType = struct {
        pub fn getValue(self: *@This()) f32 { // Wrong - should be Ints (i32 or i64)
            _ = self;
            return 3.14;
        }
        pub fn process(self: *@This()) void {
            _ = self;
        }
    };

    try std.testing.expect(OptConstraintInterface.check(WithGetValue));
    try std.testing.expect(OptConstraintInterface.check(WithoutGetValue));
    try std.testing.expect(!OptConstraintInterface.check(WrongReturnType));
}

test "mixed optional and constraint features" {
    const MixedInterface = Interface(.{
        // Required with constraint
        .getNumber = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Numeric),
        // Optional with constraint
        .getValue = OptionalConstraint(fn (*Self) TypeConstraints.PrimitiveTypes.Ints),
        // Optional with default
        .getName = OptionalDefault(fn (*Self) []const u8, struct {
            fn default(self: anytype) []const u8 {
                _ = self;
                return "default";
            }
        }.default),
        // Regular optional
        .describe = Optional(fn (*Self) []const u8),
    });

    const FullImpl = struct {
        pub fn getNumber(self: *@This()) f32 {
            _ = self;
            return 3.14;
        }
        pub fn getValue(self: *@This()) i32 {
            _ = self;
            return 42;
        }
        pub fn getName(self: *@This()) []const u8 {
            _ = self;
            return "full";
        }
        pub fn describe(self: *@This()) []const u8 {
            _ = self;
            return "complete implementation";
        }
    };

    const MinimalImpl = struct {
        pub fn getNumber(self: *@This()) u64 {
            _ = self;
            return 999;
        }
        // All optional methods omitted
    };

    try std.testing.expect(MixedInterface.check(FullImpl));
    try std.testing.expect(MixedInterface.check(MinimalImpl));
}

test "optional constraint with default" {
    const OptConstraintDefaultInterface = Interface(.{
        .calculate = OptionalConstraintDefault(fn (*Self, TypeConstraints.PrimitiveTypes.Numeric) TypeConstraints.PrimitiveTypes.Numeric, struct {
            fn default(self: anytype, value: anytype) @TypeOf(value) {
                _ = self;
                return value * 2;
            }
        }.default),
        .required = fn (*Self) void,
    });

    const WithCalculate = struct {
        pub fn calculate(self: *@This(), value: f32) f32 {
            _ = self;
            return value * 3; // Custom implementation
        }
        pub fn required(self: *@This()) void {
            _ = self;
        }
    };

    const WithoutCalculate = struct {
        pub fn required(self: *@This()) void {
            _ = self;
        }
    };

    const WrongSignature = struct {
        pub fn calculate(self: *@This(), value: []const u8) []const u8 { // Wrong types
            _ = self;
            return value;
        }
        pub fn required(self: *@This()) void {
            _ = self;
        }
    };

    try std.testing.expect(OptConstraintDefaultInterface.check(WithCalculate));
    try std.testing.expect(OptConstraintDefaultInterface.check(WithoutCalculate));
    try std.testing.expect(!OptConstraintDefaultInterface.check(WrongSignature));
}

test "optional constraint default edge cases" {
    // Test various edge cases for OptionalConstraintDefault
    const EdgeInterface = Interface(.{
        // Return type must match input type
        .identity = OptionalConstraintDefault(fn (*Self, TypeConstraints.PrimitiveTypes.Numeric) TypeConstraints.PrimitiveTypes.Numeric, struct {
            fn d(self: anytype, v: anytype) @TypeOf(v) {
                _ = self;
                return v;
            }
        }.d),

        // Multiple constrained parameters
        .combine = OptionalConstraintDefault(fn (*Self, TypeConstraints.PrimitiveTypes.Ints, TypeConstraints.PrimitiveTypes.Floats) TypeConstraints.PrimitiveTypes.Floats, struct {
            fn d(self: anytype, i: anytype, f: anytype) @TypeOf(f) {
                _ = self;
                _ = i;
                return f;
            }
        }.d),

        // Void return with constraints
        .process = OptionalConstraintDefault(fn (*Self, TypeConstraints.PrimitiveTypes.Ints) void, struct {
            fn d(self: anytype, v: anytype) void {
                _ = self;
                _ = v;
            }
        }.d),
    });

    // Valid implementation with all methods
    const ValidFull = struct {
        pub fn identity(self: *@This(), v: u32) u32 {
            _ = self;
            return v + 1;
        }
        pub fn combine(self: *@This(), i: i64, f: f32) f32 {
            _ = self;
            return f + @as(f32, @floatFromInt(i));
        }
        pub fn process(self: *@This(), v: i8) void {
            _ = self;
            _ = v;
        }
    };

    // Valid with no optional methods (using defaults)
    const ValidMinimal = struct {};

    // Invalid: wrong parameter types
    const InvalidParams = struct {
        pub fn identity(self: *@This(), v: []const u8) []const u8 {
            _ = self;
            return v;
        }
    };

    // Invalid: mismatched return type
    const InvalidReturn = struct {
        pub fn combine(self: *@This(), i: i32, f: f64) i32 { // Should return f64
            _ = self;
            _ = f;
            return i;
        }
    };

    try std.testing.expect(EdgeInterface.check(ValidFull));
    try std.testing.expect(EdgeInterface.check(ValidMinimal));
    try std.testing.expect(!EdgeInterface.check(InvalidParams));
    try std.testing.expect(!EdgeInterface.check(InvalidReturn));
}

test "comprehensive interface combinations" {
    // Test all possible combinations
    const ComprehensiveInterface = Interface(.{
        // 1. Regular method (required, no constraints, no default)
        .regular = fn (*Self) void,

        // 2. Required with constraint
        .requiredConstraint = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Ints),

        // 3. Optional only
        .optionalOnly = Optional(fn (*Self) bool),

        // 4. Optional with default
        .optionalDefault = OptionalDefault(fn (*Self) []const u8, struct {
            fn d(self: anytype) []const u8 {
                _ = self;
                return "default";
            }
        }.d),

        // 5. Optional with constraint
        .optionalConstraint = OptionalConstraint(fn (*Self) TypeConstraints.PrimitiveTypes.Floats),

        // 6. Optional with constraint and default
        .optionalConstraintDefault = OptionalConstraintDefault(fn (*Self, TypeConstraints.PrimitiveTypes.Ints) TypeConstraints.PrimitiveTypes.Ints, struct {
            fn d(self: anytype, v: anytype) @TypeOf(v) {
                _ = self;
                return v + 1;
            }
        }.d),
    });

    // Test struct with all methods implemented
    const CompleteImpl = struct {
        pub fn regular(self: *@This()) void {
            _ = self;
        }
        pub fn requiredConstraint(self: *@This()) u32 {
            _ = self;
            return 123;
        }
        pub fn optionalOnly(self: *@This()) bool {
            _ = self;
            return true;
        }
        pub fn optionalDefault(self: *@This()) []const u8 {
            _ = self;
            return "custom";
        }
        pub fn optionalConstraint(self: *@This()) f64 {
            _ = self;
            return 3.14;
        }
        pub fn optionalConstraintDefault(self: *@This(), v: i64) i64 {
            _ = self;
            return v * 2;
        }
    };

    // Test struct with only required methods
    const MinimalImpl = struct {
        pub fn regular(self: *@This()) void {
            _ = self;
        }
        pub fn requiredConstraint(self: *@This()) i8 { // Different int type
            _ = self;
            return -42;
        }
    };

    // Test struct with some optional methods
    const PartialImpl = struct {
        pub fn regular(self: *@This()) void {
            _ = self;
        }
        pub fn requiredConstraint(self: *@This()) usize {
            _ = self;
            return 999;
        }
        pub fn optionalConstraint(self: *@This()) f32 { // Using f32 instead of f64
            _ = self;
            return 2.5;
        }
        // optionalOnly, optionalDefault, and optionalConstraintDefault not implemented
    };

    try std.testing.expect(ComprehensiveInterface.check(CompleteImpl));
    try std.testing.expect(ComprehensiveInterface.check(MinimalImpl));
    try std.testing.expect(ComprehensiveInterface.check(PartialImpl));
}

test "constraint edge cases" {
    // Test with various constraint combinations
    const EdgeCaseInterface = Interface(.{
        // Multiple parameter constraints
        .multiParam = Constraint(fn (*Self, TypeConstraints.PrimitiveTypes.Ints, TypeConstraints.PrimitiveTypes.Floats) void),

        // Return type constraint
        .returnConstraint = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.IndexTypes),

        // Optional with multiple constraints
        .optMultiConstraint = OptionalConstraint(fn (*Self, TypeConstraints.PrimitiveTypes.Signed, TypeConstraints.PrimitiveTypes.Unsigned) TypeConstraints.PrimitiveTypes.Floats),

        // Complex constraint combinations
        .complexConstraint = OptionalConstraintDefault(fn (*Self, TypeConstraints.AllOf(.{ TypeConstraints.PrimitiveTypes.Ints, TypeConstraints.PrimitiveTypes.Signed })) void, struct {
            fn d(self: anytype, v: anytype) void {
                _ = self;
                _ = v;
            }
        }.d),
    });

    const ValidImpl = struct {
        pub fn multiParam(self: *@This(), a: i32, b: f64) void {
            _ = self;
            _ = a;
            _ = b;
        }
        pub fn returnConstraint(self: *@This()) usize {
            _ = self;
            return 42;
        }
        pub fn optMultiConstraint(self: *@This(), a: i64, b: u32) f16 {
            _ = self;
            _ = a;
            _ = b;
            return 1.5;
        }
        // complexConstraint is optional with default
    };

    const InvalidImpl1 = struct {
        pub fn multiParam(self: *@This(), a: f32, b: f64) void { // Wrong first param type
            _ = self;
            _ = a;
            _ = b;
        }
        pub fn returnConstraint(self: *@This()) usize {
            _ = self;
            return 42;
        }
    };

    const InvalidImpl2 = struct {
        pub fn multiParam(self: *@This(), a: i32, b: f64) void {
            _ = self;
            _ = a;
            _ = b;
        }
        pub fn returnConstraint(self: *@This()) i32 { // Wrong return type - not an IndexType
            _ = self;
            return 42;
        }
    };

    try std.testing.expect(EdgeCaseInterface.check(ValidImpl));
    try std.testing.expect(!EdgeCaseInterface.check(InvalidImpl1));
    try std.testing.expect(!EdgeCaseInterface.check(InvalidImpl2));
}

test "self type variations with constraints" {
    const SelfConstraintInterface = Interface(.{
        // Regular self-returning method (not a constraint)
        .clone = fn (*const Self) Self,

        // Optional with self pointer
        .transform = Optional(fn (*Self, *const Self) void),

        // Complex self usage with default
        .merge = OptionalDefault(fn (*Self, *const Self) *Self, struct {
            fn d(self: anytype, other: anytype) @TypeOf(self) {
                _ = other;
                return self;
            }
        }.d),
    });

    const SelfImpl = struct {
        value: i32,

        pub fn clone(self: *const @This()) @This() {
            return self.*;
        }
        pub fn transform(self: *@This(), other: *const @This()) void {
            self.value = other.value;
        }
        // merge uses default
    };

    const MinimalSelfImpl = struct {
        pub fn clone(self: *const @This()) @This() {
            return self.*;
        }
        // Both optional methods omitted
    };

    try std.testing.expect(SelfConstraintInterface.check(SelfImpl));
    try std.testing.expect(SelfConstraintInterface.check(MinimalSelfImpl));
}

test "failure cases for all combinations" {
    const StrictInterface = Interface(.{
        .required = fn (*Self) void,
        .requiredConstraint = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Ints),
    });

    // Missing required method
    const MissingRequired = struct {
        pub fn requiredConstraint(self: *@This()) i32 {
            _ = self;
            return 42;
        }
    };

    // Wrong constraint type
    const WrongConstraint = struct {
        pub fn required(self: *@This()) void {
            _ = self;
        }
        pub fn requiredConstraint(self: *@This()) f32 { // Should be Ints
            _ = self;
            return 3.14;
        }
    };

    try std.testing.expect(!StrictInterface.check(MissingRequired));
    try std.testing.expect(!StrictInterface.check(WrongConstraint));
}

test "isolated self substitution in error union" {
    // Most minimal test possible
    const MinimalInterface = Interface(.{
        .make = fn () anyerror!Self,
    });

    const Impl1 = struct {
        pub fn make() anyerror!@This() {
            return @This(){};
        }
    };

    const Impl2 = struct {
        pub fn make() anyerror!@This() {
            return @This(){};
        }
    };

    try std.testing.expect(MinimalInterface.check(Impl1));
    try std.testing.expect(MinimalInterface.check(Impl2));
}

test "debug deserialize signature matching" {
    // Test the exact pattern used in Serializable interface
    const TestInterface = Interface(.{
        .deserialize = fn ([]const u8) anyerror!Self,
    });

    const TestType1 = struct {
        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            _ = bytes;
            return error.NotImplemented;
        }
    };

    const TestType2 = struct {
        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            _ = bytes;
            return error.NotImplemented;
        }
    };

    // Test both structs use @This()
    try std.testing.expect(TestInterface.check(TestType1));
    try std.testing.expect(TestInterface.check(TestType2));

    // Test the actual Point struct pattern
    const Point = struct {
        x: f32,
        y: f32,

        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            if (bytes.len < 8) return error.InvalidData;
            return .{
                .x = @bitCast(bytes[0..4].*),
                .y = @bitCast(bytes[4..8].*),
            };
        }
    };

    try std.testing.expect(TestInterface.check(Point));
}

test "simple error union self return" {
    // Simplified test to isolate the issue
    const TestInterface = Interface(.{
        .create = fn (i32) anyerror!Self,
    });

    const TestStruct = struct {
        value: i32,
        pub fn create(val: i32) anyerror!@This() {
            return .{ .value = val };
        }
    };

    const TestStruct2 = struct {
        value: i32,
        pub fn create(val: i32) anyerror!@This() {
            return .{ .value = val };
        }
    };

    try std.testing.expect(TestInterface.check(TestStruct));
    try std.testing.expect(TestInterface.check(TestStruct2));
}

test "gradual serializable build" {
    // Test 1: Just serialize
    const S1 = Interface(.{
        .serialize = fn (*const Self, *std.ArrayList(u8)) anyerror!void,
    });

    const P1 = struct {
        x: f32,
        pub fn serialize(self: *const @This(), writer: *std.ArrayList(u8)) anyerror!void {
            try writer.appendSlice(std.mem.asBytes(&self.x));
        }
    };

    try std.testing.expect(S1.check(P1));

    // Test 2: Add deserialize
    const S2 = Interface(.{
        .serialize = fn (*const Self, *std.ArrayList(u8)) anyerror!void,
        .deserialize = fn ([]const u8) anyerror!Self,
    });

    const P2 = struct {
        x: f32,
        pub fn serialize(self: *const @This(), writer: *std.ArrayList(u8)) anyerror!void {
            try writer.appendSlice(std.mem.asBytes(&self.x));
        }
        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            _ = bytes;
            return @This(){ .x = 0 };
        }
    };

    try std.testing.expect(S2.check(P2));

    // Test 3: Add getSerializedSize with constraint
    const S3 = Interface(.{
        .serialize = fn (*const Self, *std.ArrayList(u8)) anyerror!void,
        .deserialize = fn ([]const u8) anyerror!Self,
        .getSerializedSize = OptionalConstraint(fn (*const Self) TypeConstraints.PrimitiveTypes.IndexTypes),
    });

    const P3 = struct {
        x: f32,
        pub fn serialize(self: *const @This(), writer: *std.ArrayList(u8)) anyerror!void {
            try writer.appendSlice(std.mem.asBytes(&self.x));
        }
        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            _ = bytes;
            return @This(){ .x = 0 };
        }
        pub fn getSerializedSize(self: *const @This()) usize {
            _ = self;
            return 4;
        }
    };

    try std.testing.expect(S3.check(P3));
}

test "optional constraint with self" {
    const OptInterface = Interface(.{
        .getSize = OptionalConstraint(fn (*const Self) TypeConstraints.PrimitiveTypes.IndexTypes),
    });

    const ImplWithSize = struct {
        pub fn getSize(self: *const @This()) usize {
            _ = self;
            return 0;
        }
    };

    try std.testing.expect(OptInterface.check(ImplWithSize));

    // Also test without the optional method
    const ImplWithoutSize = struct {};

    try std.testing.expect(OptInterface.check(ImplWithoutSize));
}

test "serializable pattern test" {
    const SimpleSerializable = Interface(.{
        .serialize = fn (*const Self, *std.ArrayList(u8)) anyerror!void,
        .deserialize = fn ([]const u8) anyerror!Self,
    });

    const SimplePoint = struct {
        x: f32,

        pub fn serialize(self: *const @This(), writer: *std.ArrayList(u8)) anyerror!void {
            try writer.appendSlice(std.mem.asBytes(&self.x));
        }

        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            if (bytes.len < 4) return error.InvalidData;
            return @This(){ .x = @bitCast(bytes[0..4].*) };
        }
    };

    try std.testing.expect(SimpleSerializable.check(SimplePoint));
}

test "error union self substitution" {
    // Direct test of anyerror!Self pattern
    const ErrInterface = Interface(.{
        .makeErr = fn () anyerror!Self,
    });

    const ErrImpl = struct {
        pub fn makeErr() anyerror!@This() {
            return @This(){};
        }
    };

    try std.testing.expect(ErrInterface.check(ErrImpl));

    // Test with parameters too
    const ParamErrInterface = Interface(.{
        .convert = fn ([]const u8) anyerror!Self,
    });

    const ParamErrImpl = struct {
        pub fn convert(data: []const u8) anyerror!@This() {
            _ = data;
            return @This(){};
        }
    };

    try std.testing.expect(ParamErrInterface.check(ParamErrImpl));
}

test "basic self type check" {
    // Test that Self is a unique type
    const TestSelf = struct {};
    try std.testing.expect(Self != TestSelf);
    try std.testing.expect(Self == Self);

    // Test basic interface with Self return
    const BasicInterface = Interface(.{
        .getSelf = fn () Self,
    });

    const BasicImpl = struct {
        pub fn getSelf() @This() {
            return @This(){};
        }
    };

    try std.testing.expect(BasicInterface.check(BasicImpl));
}

test "debug self substitution" {
    const TestInterface = Interface(.{
        .deserialize = fn ([]const u8) anyerror!Self,
    });

    const TestStruct = struct {
        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            _ = bytes;
            return @This(){};
        }
    };

    // This should pass
    try std.testing.expect(TestInterface.check(TestStruct));

    // Let's also test with error return
    const TestStruct2 = struct {
        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            _ = bytes;
            return error.NotImplemented;
        }
    };

    try std.testing.expect(TestInterface.check(TestStruct2));
}

test "minimal deserialize test" {
    const TestInterface = Interface(.{
        .deserialize = fn ([]const u8) anyerror!Self,
    });

    const TestStruct = struct {
        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            _ = bytes;
            return @This(){};
        }
    };

    try std.testing.expect(TestInterface.check(TestStruct));
}

test "practical interface usage example" {
    // A realistic example: Serializable interface
    const Serializable = Interface(.{
        // Required: serialize to bytes
        .serialize = fn (*const Self, *std.ArrayList(u8)) anyerror!void,

        // Required: deserialize from bytes - using static method pattern
        .deserialize = fn ([]const u8) anyerror!Self,

        // Optional: get serialized size hint
        .getSerializedSize = OptionalConstraint(fn (*const Self) TypeConstraints.PrimitiveTypes.IndexTypes),

        // Optional with default: get format version
        .getFormatVersion = OptionalDefault(fn (*const Self) u32, struct {
            fn d(self: anytype) u32 {
                _ = self;
                return 1; // Default version
            }
        }.d),

        // Optional with constraint and default: validate before serialization
        .validate = OptionalDefault(fn (*const Self) anyerror!void, struct {
            fn d(self: anytype) anyerror!void {
                _ = self;
                // Default: no validation
            }
        }.d),
    });

    const Point = struct {
        x: f32,
        y: f32,

        pub fn serialize(self: *const @This(), writer: *std.ArrayList(u8)) anyerror!void {
            try writer.appendSlice(std.mem.asBytes(&self.x));
            try writer.appendSlice(std.mem.asBytes(&self.y));
        }

        pub fn deserialize(bytes: []const u8) anyerror!@This() {
            if (bytes.len < 8) return error.InvalidData;
            return @This(){
                .x = @bitCast(bytes[0..4].*),
                .y = @bitCast(bytes[4..8].*),
            };
        }

        pub fn getSerializedSize(self: *const @This()) usize {
            _ = self;
            return 8;
        }
    };

    // Test both structs with @This()
    try std.testing.expect(Serializable.check(Point));
}

test "type constraint categories" {
    // Test all the predefined type constraint categories
    const NumericInterface = Interface(.{
        .getInt = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Ints),
        .getFloat = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Floats),
        .getNumeric = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Numeric),
        .getSigned = OptionalConstraint(fn (*Self) TypeConstraints.PrimitiveTypes.Signed),
        .getCounter = OptionalConstraint(fn (*Self) TypeConstraints.PrimitiveTypes.CounterTypes),
        .getIndex = OptionalConstraintDefault(fn (*Self) TypeConstraints.PrimitiveTypes.IndexTypes, struct {
            fn d(self: anytype) usize {
                _ = self;
                return 0;
            }
        }.d),
    });

    const NumericImpl = struct {
        pub fn getInt(self: *@This()) u64 {
            _ = self;
            return 42;
        }
        pub fn getFloat(self: *@This()) f32 {
            _ = self;
            return 3.14;
        }
        pub fn getNumeric(self: *@This()) i32 { // Can be int or float
            _ = self;
            return -10;
        }
        pub fn getSigned(self: *@This()) i64 {
            _ = self;
            return -999;
        }
        pub fn getCounter(self: *@This()) usize {
            _ = self;
            return 100;
        }
        // Using default for getIndex
    };

    try std.testing.expect(NumericInterface.check(NumericImpl));

    // Test category constraints
    const CategoryInterface = Interface(.{
        .getStruct = Constraint(fn (*Self) TypeConstraints.Struct),
    });

    const CategoryImpl = struct {
        pub fn getStruct(self: *@This()) struct { x: i32 } {
            _ = self;
            return .{ .x = 42 };
        }
    };

    try std.testing.expect(CategoryInterface.check(CategoryImpl));
}

test "runtime wrapper with defaults example" {
    // Example of how to create a runtime wrapper that uses default implementations
    const WithDefaults = struct {
        pub fn wrap(comptime T: type, comptime InterfaceSpec: anytype) type {
            return struct {
                inner: T,

                const InterfaceChecker = Interface(InterfaceSpec);

                pub fn init(inner: T) @This() {
                    // Verify at compile time that T implements required methods
                    comptime {
                        InterfaceChecker.assert(T);
                    }
                    return .{ .inner = inner };
                }

                // Example: If getName has a default and T doesn't implement it,
                // the wrapper could provide it
                pub fn getName(self: *@This()) []const u8 {
                    if (@hasDecl(T, "getName")) {
                        return self.inner.getName();
                    } else if (@hasField(@TypeOf(InterfaceSpec), "getName")) {
                        const spec = @field(InterfaceSpec, "getName");
                        if (@hasDecl(spec, "has_default")) {
                            return spec.default(&self.inner);
                        }
                    }
                    return "no name";
                }
            };
        }
    };

    const TestInterface = .{
        .getName = OptionalDefault(fn (*Self) []const u8, struct {
            fn d(self: anytype) []const u8 {
                _ = self;
                return "default name";
            }
        }.d),
        .getId = fn (*Self) u32,
    };

    const ImplWithoutName = struct {
        id: u32,
        pub fn getId(self: *@This()) u32 {
            return self.id;
        }
    };

    const Wrapped = WithDefaults.wrap(ImplWithoutName, TestInterface);
    var instance = Wrapped.init(.{ .id = 42 });

    try std.testing.expectEqual(@as(u32, 42), instance.inner.getId());
    try std.testing.expectEqualStrings("default name", instance.getName());
}

test "all linear combinations summary" {
    // This test documents all possible linear combinations of features
    const AllCombinations = Interface(.{
        // Base cases (no modifiers)
        .regular = fn (*Self) void,

        // Single modifiers
        .onlyOptional = Optional(fn (*Self) void),
        .onlyConstraint = Constraint(fn (*Self) TypeConstraints.PrimitiveTypes.Numeric),
        // Note: Default without Optional doesn't make sense

        // Two modifiers
        .optionalConstraint = OptionalConstraint(fn (*Self) TypeConstraints.PrimitiveTypes.Ints),
        .optionalDefault = OptionalDefault(fn (*Self) bool, struct {
            fn d(s: anytype) bool {
                _ = s;
                return false;
            }
        }.d),
        // Note: Constraint + Default without Optional doesn't make sense

        // Three modifiers
        .optionalConstraintDefault = OptionalConstraintDefault(fn (*Self) TypeConstraints.PrimitiveTypes.Ints, struct {
            fn d(s: anytype) i32 {
                _ = s;
                return 0;
            }
        }.d),
    });

    const TestImpl = struct {
        pub fn regular(self: *@This()) void {
            _ = self;
        }
        pub fn onlyConstraint(self: *@This()) f64 {
            _ = self;
            return 1.0;
        }
        // All optional methods can be omitted
    };

    try std.testing.expect(AllCombinations.check(TestImpl));

    // Demonstrate that constraint works with different numeric types
    const AnotherImpl = struct {
        pub fn regular(self: *@This()) void {
            _ = self;
        }
        pub fn onlyConstraint(self: *@This()) u32 {
            _ = self;
            return 42;
        } // Different numeric type
        pub fn optionalConstraint(self: *@This()) i64 {
            _ = self;
            return -1;
        } // Implements optional
    };

    try std.testing.expect(AllCombinations.check(AnotherImpl));
}
