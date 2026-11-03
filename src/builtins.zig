const std = @import("std");
const Value = @import("value.zig").Value;

const BuiltinFn = *const fn (args: []const Value) Value;
pub const BuiltinMap = std.StringHashMap(BuiltinFn);

pub fn init(allocator: std.mem.Allocator) !BuiltinMap {
    var builtins = BuiltinMap.init(allocator);
    // Cleans up if registration fails. On success, caller takes ownership and normal defer handles cleanup.
    errdefer builtins.deinit();

    try builtins.put("+", &add);
    return builtins;
}

fn add(args: []const Value) Value {
    var sum: i32 = 0;
    for (args) |arg| {
        sum += switch (arg) {
            .int => |int| int,
            else => 0, // For simplicity, treat non-integer values as 0
        };
    }
    return .{ .int = sum };
}
