const std = @import("std");
const Value = @import("value.zig").Value;

pub fn print(writer: *std.Io.Writer, value: Value) std.Io.Writer.Error!void {
    try switch (value) {
        .int => |int| writer.print("{d}", .{int}),
        .sym => |sym| writer.writeAll(sym),
        .str => |str| {
            try writer.writeByte('"');

            for (str) |byte| {
                try switch (byte) {
                    '\\' => writer.writeAll("\\\\"),
                    '"' => writer.writeAll("\\\""),
                    '\n' => writer.writeAll("\\n"),
                    '\t' => writer.writeAll("\\t"),
                    '\r' => writer.writeAll("\\r"),
                    else => writer.writeByte(byte),
                };
            }

            try writer.writeByte('"');
        },
        .list => |list| {
            try writer.writeByte('(');

            for (list, 0..) |element, i| {
                if (i != 0) {
                    try writer.writeByte(' ');
                }
                try print(writer, element);
            }

            try writer.writeByte(')');
        },
    };
}

test "print list value to a fixed-buffer writer" {
    const cases = [_]struct {
        val: Value,
        expected: []const u8,
    }{
        .{
            .val = .{
                .list = &.{},
            },
            .expected = "()",
        },
        .{
            .val = .{
                .list = &.{
                    .{ .int = 420 },
                },
            },
            .expected = "(420)",
        },
        .{
            .val = .{
                .list = &.{
                    .{ .int = 420 },
                    .{ .str = "blazeit" },
                },
            },
            .expected = "(420 \"blazeit\")",
        },
        .{
            .val = .{
                .list = &.{
                    .{ .int = 1 },
                    .{
                        .list = &.{
                            .{ .int = 2 },
                        },
                    },
                    .{ .int = 3 },
                },
            },
            .expected = "(1 (2) 3)",
        },
    };

    for (cases) |case| {
        var buf: [64]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);

        try print(
            &writer,
            case.val,
        );

        try std.testing.expectEqualStrings(
            case.expected,
            writer.buffered(),
        );
    }
}

test "print integer value to fixed-buffer writer" {
    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try print(&writer, .{ .int = 42 });

    try std.testing.expectEqualStrings("42", writer.buffered());
}

test "print symbol value to fixed-buffer writer" {
    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try print(&writer, .{ .sym = "YOLO" });

    try std.testing.expectEqualStrings("YOLO", writer.buffered());
}

test "print string value to fixed-buffer writer" {
    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try print(&writer, .{ .str = "YOLO" });

    try std.testing.expectEqualStrings("\"YOLO\"", writer.buffered());
}

test "print escaped string value to fixed-buffer writer" {
    const cases = [_]struct {
        contents: []const u8,
        expected: []const u8,
    }{
        .{
            .contents = "hello \"world\"",
            .expected = "\"hello \\\"world\\\"\"",
        },
        .{
            .contents = "\\",
            .expected = "\"\\\\\"",
        },
        .{
            .contents = "\n",
            .expected = "\"\\n\"",
        },
        .{
            .contents = "\t",
            .expected = "\"\\t\"",
        },
        .{
            .contents = "\r",
            .expected = "\"\\r\"",
        },
        .{
            .contents = "\\n",
            .expected = "\"\\\\n\"",
        },
        .{
            .contents = "\t\n\"YOLO\"\\\r",
            .expected = "\"\\t\\n\\\"YOLO\\\"\\\\\\r\"",
        },
    };

    for (cases) |case| {
        var buf: [64]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);

        try print(&writer, .{ .str = case.contents });

        try std.testing.expectEqualStrings(case.expected, writer.buffered());
    }
}
