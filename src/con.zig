const std = @import("std");

fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();
        buffer: std.fifo.LinearFifo(T, .Dynamic),
        condition: std.Thread.Condition = .{},
        mutex: std.Thread.Mutex = .{},
        closed: std.atomic.Value(bool),

        fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .buffer = std.fifo.LinearFifo(T, .Dynamic).init(allocator),
                .closed = std.atomic.Value(bool).init(false),
            };
        }

        fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed.load(.seq_cst)) return error.ChannelClosed;
            try self.buffer.writeItem(value);
            self.condition.signal();
        }

        fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (true) {
                if (self.buffer.readItem()) |value| {
                    return value;
                }
                if (self.closed.load(.seq_cst)) return error.ChannelClosed;
                self.condition.wait(&self.mutex);
            }
        }

        fn tryRecv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.buffer.readItem();
        }

        fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.closed.store(true, .seq_cst);
            self.condition.broadcast();
        }
    };
}

test "channel operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var channel = Channel(i32).init(allocator);
    defer channel.deinit();

    try channel.send(42);
    const value = try channel.recv();
    try std.testing.expect(value == 42);
}

test "try recv empty" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var channel = Channel(i32).init(allocator);
    defer channel.deinit();

    try std.testing.expect(channel.tryRecv() == null);
}

test "close channel" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var channel = Channel(i32).init(allocator);
    defer channel.deinit();

    channel.close();
    try std.testing.expectError(error.ChannelClosed, channel.send(42));
    try std.testing.expectError(error.ChannelClosed, channel.recv());
}
