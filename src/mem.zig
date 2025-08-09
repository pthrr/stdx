const std = @import("std");

pub fn UniquePtr(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: ?*T,
        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex = .{},

        /// Create a new UniquePtr with the given arguments
        pub fn init(allocator: std.mem.Allocator, args: anytype) !Self {
            const ptr = try allocator.create(T);
            errdefer allocator.destroy(ptr);

            const call_result = @call(.auto, T.init, args);
            ptr.* = if (@typeInfo(@TypeOf(call_result)) == .error_union) try call_result else call_result;

            return Self{
                .ptr = ptr,
                .allocator = allocator,
            };
        }

        /// Destroy the owned object and free memory
        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.ptr) |ptr| {
                if (@hasDecl(T, "deinit")) {
                    ptr.deinit();
                }
                self.allocator.destroy(ptr);
                self.ptr = null;
            }
        }

        /// Move ownership to a new UniquePtr, leaving this one empty
        pub fn move(self: *Self) Self {
            self.mutex.lock();
            defer self.mutex.unlock();

            const result = Self{
                .ptr = self.ptr,
                .allocator = self.allocator,
            };
            self.ptr = null;
            return result;
        }

        /// Get raw pointer to the owned object (can return null if moved)
        pub fn get(self: *Self) ?*T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.ptr;
        }

        /// Release ownership and return the raw pointer
        pub fn release(self: *Self) ?*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const ptr = self.ptr;
            self.ptr = null;
            return ptr;
        }

        /// Reset with a new pointer, destroying the old one
        pub fn reset(self: *Self, new_ptr: ?*T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.ptr) |old_ptr| {
                if (@hasDecl(T, "deinit")) {
                    old_ptr.deinit();
                }
                self.allocator.destroy(old_ptr);
            }
            self.ptr = new_ptr;
        }
    };
}

pub fn SharedPtr(comptime T: type) type {
    return struct {
        const Self = @This();

        const ControlBlock = struct {
            ref_count: std.atomic.Value(u32),
            weak_count: std.atomic.Value(u32),
            ptr: ?*T,
            allocator: std.mem.Allocator,
            mutex: std.Thread.Mutex = .{},

            fn destroy(self: *ControlBlock) void {
                self.mutex.lock();
                defer self.mutex.unlock();

                if (self.ptr) |ptr| {
                    if (@hasDecl(T, "deinit")) {
                        ptr.deinit();
                    }
                    self.allocator.destroy(ptr);
                    self.ptr = null;
                }
            }

            fn shouldDestroyControlBlock(self: *ControlBlock) bool {
                return self.ref_count.load(.seq_cst) == 0 and
                    self.weak_count.load(.seq_cst) == 0;
            }
        };

        control_block: ?*ControlBlock,

        /// Create a new SharedPtr with the given arguments
        pub fn init(allocator: std.mem.Allocator, args: anytype) !Self {
            const ptr = try allocator.create(T);
            errdefer allocator.destroy(ptr);

            const call_result = @call(.auto, T.init, args);
            ptr.* = if (@typeInfo(@TypeOf(call_result)) == .error_union) try call_result else call_result;

            const control_block = try allocator.create(ControlBlock);
            control_block.* = ControlBlock{
                .ref_count = std.atomic.Value(u32).init(1),
                .weak_count = std.atomic.Value(u32).init(0),
                .ptr = ptr,
                .allocator = allocator,
            };

            return Self{ .control_block = control_block };
        }

        /// Decrement reference count and destroy if last reference
        pub fn deinit(self: *Self) void {
            if (self.control_block) |cb| {
                const old_ref = cb.ref_count.fetchSub(1, .seq_cst);
                if (old_ref == 1) {
                    // Last reference - destroy the object
                    cb.destroy();

                    // Check if we should destroy control block
                    if (cb.shouldDestroyControlBlock()) {
                        const allocator = cb.allocator;
                        allocator.destroy(cb);
                    }
                }
                self.control_block = null;
            }
        }

        /// Create a new SharedPtr sharing ownership
        pub fn clone(self: *Self) Self {
            if (self.control_block) |cb| {
                _ = cb.ref_count.fetchAdd(1, .seq_cst);
                return Self{ .control_block = cb };
            }
            return Self{ .control_block = null };
        }

        /// Get raw pointer to the shared object
        pub fn get(self: *Self) ?*T {
            if (self.control_block) |cb| {
                cb.mutex.lock();
                defer cb.mutex.unlock();
                return cb.ptr;
            }
            return null;
        }

        /// Get current reference count
        pub fn useCount(self: *const Self) u32 {
            return if (self.control_block) |cb| cb.ref_count.load(.seq_cst) else 0;
        }

        /// Create a WeakPtr from this SharedPtr
        pub fn getWeakPtr(self: *Self) WeakPtr(T) {
            return WeakPtr(T).fromShared(self);
        }

        /// Check if this SharedPtr is unique (ref count == 1)
        pub fn unique(self: *const Self) bool {
            return self.useCount() == 1;
        }
    };
}

pub fn WeakPtr(comptime T: type) type {
    return struct {
        const Self = @This();
        const ControlBlock = SharedPtr(T).ControlBlock;

        control_block: ?*ControlBlock,

        /// Create WeakPtr from SharedPtr
        pub fn fromShared(shared: *SharedPtr(T)) Self {
            if (shared.control_block) |cb| {
                _ = cb.weak_count.fetchAdd(1, .seq_cst);
                return Self{ .control_block = cb };
            }
            return Self{ .control_block = null };
        }

        /// Destroy this WeakPtr
        pub fn deinit(self: *Self) void {
            if (self.control_block) |cb| {
                const old_weak = cb.weak_count.fetchSub(1, .seq_cst);
                if (old_weak == 1 and cb.shouldDestroyControlBlock()) {
                    // Last weak reference and object already destroyed
                    const allocator = cb.allocator;
                    allocator.destroy(cb);
                }
                self.control_block = null;
            }
        }

        /// Try to convert to SharedPtr (returns null if object expired)
        pub fn lock(self: *Self) ?SharedPtr(T) {
            if (self.control_block) |cb| {
                // Try to increment ref count if still > 0
                var current = cb.ref_count.load(.seq_cst);
                while (current > 0) {
                    if (cb.ref_count.cmpxchgWeak(current, current + 1, .seq_cst, .seq_cst)) |new_current| {
                        current = new_current;
                    } else {
                        // Successfully incremented
                        return SharedPtr(T){ .control_block = cb };
                    }
                }
            }
            return null;
        }

        /// Check if the referenced object has been destroyed
        pub fn expired(self: *Self) bool {
            return if (self.control_block) |cb| cb.ref_count.load(.seq_cst) == 0 else true;
        }

        /// Get current use count of the referenced object
        pub fn useCount(self: *Self) u32 {
            return if (self.control_block) |cb| cb.ref_count.load(.seq_cst) else 0;
        }
    };
}

test "UniquePtr basic functionality" {
    const TestStruct = struct {
        value: i32,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, val: i32) !@This() {
            return .{ .value = val, .allocator = allocator };
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var unique = try UniquePtr(TestStruct).init(allocator, .{ allocator, 42 });
    defer unique.deinit();

    if (unique.get()) |ptr| {
        try std.testing.expect(ptr.value == 42);
    }

    var moved = unique.move();
    defer moved.deinit();

    try std.testing.expect(unique.get() == null);
    if (moved.get()) |ptr| {
        try std.testing.expect(ptr.value == 42);
    }
}

test "SharedPtr reference counting" {
    const TestStruct = struct {
        value: i32,
        pub fn init(val: i32) @This() {
            return .{ .value = val };
        }
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var shared1 = try SharedPtr(TestStruct).init(allocator, .{42});
    defer shared1.deinit();

    try std.testing.expect(shared1.useCount() == 1);

    var shared2 = shared1.clone();
    defer shared2.deinit();

    try std.testing.expect(shared1.useCount() == 2);
    try std.testing.expect(shared2.useCount() == 2);
}

test "WeakPtr functionality" {
    const TestStruct = struct {
        value: i32,
        pub fn init(val: i32) @This() {
            return .{ .value = val };
        }
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var shared = try SharedPtr(TestStruct).init(allocator, .{42});
    var weak = shared.getWeakPtr();
    defer weak.deinit();

    try std.testing.expect(!weak.expired());
    try std.testing.expect(weak.useCount() == 1);

    if (weak.lock()) |locked_const| {
        var locked = locked_const;
        defer locked.deinit();
        try std.testing.expect(locked.useCount() == 2);
    }

    shared.deinit();

    try std.testing.expect(weak.expired());
    try std.testing.expect(weak.lock() == null);
}
