const std = @import("std");
const Value = @import("value.zig").Value;

pub const Error = error{UnsupportedValue};

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
        sum += switch (arg) {
            .int => |int| int,
            else => return error.UnsupportedValue,
        };
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
