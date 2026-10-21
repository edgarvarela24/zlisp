const std = @import("std");

const Value = union(enum) { int: i32, list: []const Value, sym: []const u8 };

pub fn readInt(val: []const u8) !i32 {
    const trimmed = std.mem.trim(
        u8,
        val,
        &std.ascii.whitespace,
    );

    if (trimmed.len == 0) {
        return error.InvalidArgument;
    }

    return std.fmt.parseInt(i32, trimmed, 10);
}

test "basic int reading" {
    const cases = .{
        .{
            .val = "42",
            .expected = 42,
        },
        .{
            .val = "0",
            .expected = 0,
        },
        .{
            .val = "-42",
            .expected = -42,
        },
        .{
            .val = "  42  ",
            .expected = 42,
        },
    };

    inline for (cases) |case| {
        try std.testing.expectEqual(case.expected, readInt(case.val));
    }

    const error_cases = .{
        .{
            .val = "",
            .expected = error.InvalidArgument,
        },
        .{
            .val = "    ",
            .expected = error.InvalidArgument,
        },
        .{
            .val = "abc",
            .expected = error.InvalidCharacter,
        },
        .{
            .val = "2147483648",
            .expected = error.Overflow,
        },
        .{
            .val = "42abc",
            .expected = error.InvalidCharacter,
        },
        .{
            .val = "4 2",
            .expected = error.InvalidCharacter,
        },
        .{
            .val = "-",
            .expected = error.InvalidCharacter,
        },
    };

    inline for (error_cases) |case| {
        try std.testing.expectError(case.expected, readInt(case.val));
    }
}

pub fn read(allocator: std.mem.Allocator, val: []const u8) !Value {
    const trimmed = std.mem.trim(u8, val, &std.ascii.whitespace);

    if (trimmed.len == 0) {
        return error.InvalidArgument;
    }

    const has_open = std.mem.startsWith(u8, trimmed, "(");
    const has_close = std.mem.endsWith(u8, trimmed, ")");

    if (trimmed.len >= 2 and has_open and has_close) {
        var arraylist: std.ArrayList(Value) = .empty;
        defer arraylist.deinit(allocator);

        const contents = trimmed[1 .. trimmed.len - 1];
        var tokens = std.mem.tokenizeAny(u8, contents, &std.ascii.whitespace);

        while (tokens.next()) |token| {
            const v = try read(allocator, token);
            try arraylist.append(allocator, v);
        }

        const slice = try arraylist.toOwnedSlice(allocator);

        return .{
            .list = slice,
        };
    }

    var is_sym = true;
    for (trimmed) |c| {
        if (!std.ascii.isAlphabetic(c) and c != '+' and c != '-') {
            is_sym = false;
            break;
        }
    }

    if (is_sym) {
        return .{
            .sym = trimmed,
        };
    }

    const int = try readInt(val);
    return .{
        .int = int,
    };
}

test "read returns Lisp value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = .{
        .{
            .val = "42",
            .expected = 42,
        },
        .{
            .val = "-42",
            .expected = -42,
        },
        .{
            .val = "0",
            .expected = 0,
        },
    };

    inline for (cases) |case| {
        const result = try read(allocator, case.val);
        try std.testing.expectEqual(case.expected, result.int);
    }

    const error_cases = .{.{ .val = "2147483648", .expected = error.Overflow }};

    inline for (error_cases) |case| {
        try std.testing.expectError(case.expected, read(allocator, case.val));
    }
}

test "read returns a symbol" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = .{
        .{
            .val = "hello",
            .expected = "hello",
        },
        .{
            .val = "world",
            .expected = "world",
        },
        .{
            .val = "  hello  ",
            .expected = "hello",
        },
        .{
            .val = "+",
            .expected = "+",
        },
        .{
            .val = "-",
            .expected = "-",
        },
    };

    inline for (cases) |case| {
        const result = try read(allocator, case.val);
        try std.testing.expectEqualStrings(case.expected, result.sym);
    }

    try std.testing.expectError(error.InvalidCharacter, read(allocator, "he2llo"));
}

test "read returns a list with elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = .{
        .{
            .val = "()",
            .slice = &.{},
        },
        .{
            .val = "(  )",
            .slice = &.{},
        },
        .{
            .val = "   ()   ",
            .slice = &.{},
        },
        .{
            .val = "(42)",
            .slice = &.{42},
        },
        .{
            .val = "(42 7)",
            .slice = &.{ 42, 7 },
        },
        .{
            .val = "(42 7 -1)",
            .slice = &.{ 42, 7, -1 },
        },
    };

    inline for (cases) |case| {
        const result = try read(allocator, case.val);
        try std.testing.expectEqual(Value.list, std.meta.activeTag(result));
        try std.testing.expectEqual(case.slice.len, result.list.len);

        inline for (case.slice, result.list) |slice_item, list_item| {
            try std.testing.expectEqual(slice_item, list_item.int);
        }
    }
}

test "read returns a list of symbols" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = .{
        .{
            .val = "(hello world)",
            .slice = &.{ "hello", "world" },
        },
        .{
            .val = "(+ x y)",
            .slice = &.{ "+", "x", "y" },
        },
    };

    inline for (cases) |case| {
        const result = try read(allocator, case.val);
        try std.testing.expectEqual(Value.list, std.meta.activeTag(result));
        try std.testing.expectEqual(case.slice.len, result.list.len);

        inline for (case.slice, result.list) |slice_item, list_item| {
            try std.testing.expectEqualStrings(slice_item, list_item.sym);
        }
    }
}

test "read returns a list of mixed values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = .{
        .{
            .val = "(hello 69 world)",
            .slice = @as([]const Value, &.{
                .{ .sym = "hello" },
                .{ .int = 69 },
                .{ .sym = "world" },
            }),
        },
        .{
            .val = "(+ 1 2)",
            .slice = @as([]const Value, &.{
                .{ .sym = "+" },
                .{ .int = 1 },
                .{ .int = 2 },
            }),
        },
        .{ .val = "(42 (7 8))", .slice = @as([]const Value, &.{
            .{ .int = 42 },
            .{ .list = &.{
                .{ .int = 7 },
                .{ .int = 8 },
            } },
        }) },
    };

    inline for (cases) |case| {
        const result = try read(allocator, case.val);
        try std.testing.expectEqual(
            Value.list,
            std.meta.activeTag(result),
        );
        try std.testing.expectEqual(
            case.slice.len,
            result.list.len,
        );

        inline for (case.slice, result.list) |slice_item, list_item| {
            try std.testing.expectEqual(
                std.meta.activeTag(slice_item),
                std.meta.activeTag(list_item),
            );

            switch (slice_item) {
                .int => |value| {
                    try std.testing.expectEqual(value, list_item.int);
                },
                .sym => |text| {
                    try std.testing.expectEqualStrings(text, list_item.sym);
                },
                .list => {
                    return error.NestedListComparisonnotSupported;
                },
            }
        }
    }
}
