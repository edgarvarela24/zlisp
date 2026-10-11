const std = @import("std");

pub fn readInt(val: []const u8) !i32 {
    const trimmed = std.mem.trim(u8, val, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        return error.InvalidArgument;
    }

    return std.fmt.parseInt(i32, trimmed, 10);
}

test "basic int reading" {
    const cases = .{ .{ .val = "42", .expected = 42 }, .{ .val = "0", .expected = 0 }, .{ .val = "-42", .expected = -42 }, .{ .val = "  42  ", .expected = 42 } };

    inline for (cases) |case| {
        try std.testing.expectEqual(case.expected, readInt(case.val));
    }

    const errorCases = .{ .{ .val = "", .expected = error.InvalidArgument }, .{ .val = "    ", .expected = error.InvalidArgument }, .{ .val = "abc", .expected = error.InvalidCharacter }, .{ .val = "2147483648", .expected = error.Overflow } };

    inline for (errorCases) |case| {
        try std.testing.expectError(case.expected, readInt(case.val));
    }
}
