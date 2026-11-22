const std = @import("std");
const Value = @import("value.zig").Value;

pub const Error = error{ UnsupportedValue, Overflow };

const BuiltinFn = *const fn (args: []const Value) Error!Value;
pub const BuiltinMap = std.StringHashMap(BuiltinFn);

pub fn init(allocator: std.mem.Allocator) !BuiltinMap {
    var builtins = BuiltinMap.init(allocator);
    // Cleans up if registration fails. On success, caller takes ownership and normal defer handles cleanup.
    errdefer builtins.deinit();

    try builtins.put("+", &add);
    return builtins;
}

fn add(args: []const Value) !Value {
    var sum: i32 = 0;
    for (args) |arg| {
        const n = switch (arg) {
            .int => |int| int,
            else => return error.UnsupportedValue,
        };
        sum = try std.math.add(i32, sum, n);
    }
    return .{ .int = sum };
}

test "add returns error for non-integer inputs" {
    const args: []const Value = &.{
        .{ .int = 1 },
        .{ .str = "not an int" },
    };

    try std.testing.expectError(error.UnsupportedValue, add(args));
}

test "add returns error for positive overflow" {
    const args: []const Value = &.{
        .{ .int = 2147483647 }, // Max i32
        .{ .int = 1 },
    };

    try std.testing.expectError(error.Overflow, add(args));
}

test "add returns error for negative overflow" {
    const args: []const Value = &.{
        .{ .int = -2147483648 }, // Min i32
        .{ .int = -1 },
    };

    try std.testing.expectError(error.Overflow, add(args));
}

test "add returns 0 for empty args" {
    const args: []const Value = &.{}; // Empty array
    const result = try add(args);
    const expected: Value = .{ .int = 0 };
    try std.testing.expectEqual(expected, result);
}

test "add returns correct sum for one integer" {
    const args: []const Value = &.{
        .{ .int = 42 },
    };
    const result = try add(args);
    const expected: Value = .{ .int = 42 };
    try std.testing.expectEqual(expected, result);
}

test "add returns correct sum for multiple integers" {
    const args: []const Value = &.{
        .{ .int = 1 },
        .{ .int = 2 },
        .{ .int = 3 },
    };
    const result = try add(args);
    const expected: Value = .{ .int = 6 };
    try std.testing.expectEqual(expected, result);
}
