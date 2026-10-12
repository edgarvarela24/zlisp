const std = @import("std");

pub fn readInt(val: []const u8) !i32 {
    const trimmed = std.mem.trim(u8, val, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        return error.InvalidArgument;
    }

    return std.fmt.parseInt(i32, trimmed, 10);
}

test "basic int reading" {
    const cases = .{
        .{ .val = "42", .expected = 42 },
        .{ .val = "0", .expected = 0 },
        .{ .val = "-42", .expected = -42 },
        .{ .val = "  42  ", .expected = 42 },
    };

    inline for (cases) |case| {
        try std.testing.expectEqual(case.expected, readInt(case.val));
    }

    const errorCases = .{
        .{ .val = "", .expected = error.InvalidArgument },
        .{ .val = "    ", .expected = error.InvalidArgument },
        .{ .val = "abc", .expected = error.InvalidCharacter },
        .{ .val = "2147483648", .expected = error.Overflow },
        .{ .val = "42abc", .expected = error.InvalidCharacter },
        .{ .val = "4 2", .expected = error.InvalidCharacter },
        .{ .val = "-", .expected = error.InvalidCharacter },
    };

    inline for (errorCases) |case| {
        try std.testing.expectError(case.expected, readInt(case.val));
    }
}

const Value = union(enum) { int: i32, list, sym: []const u8 };

pub fn read(val: []const u8) !Value {
    const trimmed = std.mem.trim(u8, val, &std.ascii.whitespace);

    if (trimmed.len == 0) {
        return error.InvalidArgument;
    }

    const has_open = std.mem.startsWith(u8, trimmed, "(");
    const has_close = std.mem.endsWith(u8, trimmed, ")");

    if (trimmed.len >= 2 and has_open and has_close) {
        const only_whitespace = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace).len == 0;
        if (only_whitespace) {
            return .list;
        }
    }

    var is_sym = true;
    for (trimmed) |c| {
        if (!std.ascii.isAlphabetic(c) and c != '+' and c != '-') {
            is_sym = false;
            break;
        }
    }

    if (is_sym) {
        return .{ .sym = trimmed };
    }

    const int = try readInt(val);
    return .{ .int = int };
}

test "read returns Lisp value" {
    const cases = .{
        .{ .val = "42", .expected = 42 },
        .{ .val = "-42", .expected = -42 },
        .{ .val = "0", .expected = 0 },
    };

    inline for (cases) |case| {
        const result = try read(case.val);
        try std.testing.expectEqual(case.expected, result.int);
    }

    const errorCases = .{.{ .val = "2147483648", .expected = error.Overflow }};

    inline for (errorCases) |case| {
        try std.testing.expectError(case.expected, read(case.val));
    }
}

test "read returns an empty list" {
    const cases = .{
        .{ .val = "()", .expected = .list },
        .{ .val = "   ()   ", .expected = .list },
        .{ .val = "( )", .expected = .list },
    };

    inline for (cases) |case| {
        try std.testing.expectEqual(case.expected, read(case.val));
    }
}

test "read returns a symbol" {
    const cases = .{
        .{ .val = "hello", .expected = "hello" },
        .{ .val = "world", .expected = "world" },
        .{ .val = "  hello  ", .expected = "hello" },
        .{ .val = "+", .expected = "+" },
        .{ .val = "-", .expected = "-" },
    };

    inline for (cases) |case| {
        const result = try read(case.val);
        try std.testing.expectEqualStrings(case.expected, result.sym);
    }

    try std.testing.expectError(error.InvalidCharacter, read("he2llo"));
}
