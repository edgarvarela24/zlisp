const std = @import("std");

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const Value = @import("value.zig").Value;

pub const read = reader.read;
pub const print = printer.print;

test {
    _ = printer;
    _ = reader;
}

test "reader printer integration" {
    const input =
        \\(42 hello ("line\nbreak" "say \"hi\"" "a\\b") () -7)
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const value = try read(allocator, input);

    const expected: Value = .{
        .list = &.{
            .{ .int = 42 },
            .{ .sym = "hello" },
            .{
                .list = &.{
                    .{ .str = "line\nbreak" },
                    .{ .str = "say \"hi\"" },
                    .{ .str = "a\\b" },
                },
            },
            .{
                .list = &.{},
            },
            .{
                .int = -7,
            },
        },
    };

    try std.testing.expectEqualDeep(expected, value);

    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try print(&writer, value);

    try std.testing.expectEqualDeep(input, writer.buffered());

    const reread = try read(allocator, writer.buffered());
    try std.testing.expectEqualDeep(value, reread);
}
