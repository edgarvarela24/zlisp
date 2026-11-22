const std = @import("std");

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const evaluator = @import("eval.zig");
pub const Runtime = @import("runtime.zig").Runtime;

const builtins = @import("builtins.zig");
pub const Value = @import("value.zig").Value;

const read = reader.read;
const print = printer.print;
const eval = evaluator.eval;

test {
    _ = printer;
    _ = reader;
    _ = eval;
}

test "runtime read print roundtrip" {
    const input =
        \\(42 hello ("line\nbreak" "say \"hi\"" "a\\b") () -7)
    ;

    var runtime = try Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const value = try runtime.read(input);

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

    try runtime.print(&writer, value);

    try std.testing.expectEqualStrings(input, writer.buffered());

    const reread = try runtime.read(writer.buffered());
    try std.testing.expectEqualDeep(value, reread);
}

test "runtime reader printer evaluator integration" {
    const input = "(+ 1 2 3 4)";

    var runtime = try Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const value = try runtime.read(input);

    const expected: Value = .{
        .list = &.{
            .{ .sym = "+" },
            .{ .int = 1 },
            .{ .int = 2 },
            .{ .int = 3 },
            .{ .int = 4 },
        },
    };

    try std.testing.expectEqualDeep(expected, value);

    const result = try runtime.eval(value);

    const expected_result: Value = .{ .int = 10 };

    try std.testing.expectEqualDeep(expected_result, result);

    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try runtime.print(&writer, result);

    try std.testing.expectEqualStrings("10", writer.buffered());
}
