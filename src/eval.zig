const std = @import("std");
const Value = @import("value.zig").Value;

pub fn eval(value: Value) !Value {
    return switch (value) {
        .int => |int| .{ .int = int },
        .str => |str| .{ .str = str },
        .list => |list| {
            if (list.len == 0) {
                return .{ .list = &.{} };
            }
            const first = list[0];
            return switch (first) {
                .sym => |sym| {
                    return switch (sym[0]) {
                        '+' => {
                            return .{ .int = list[1].int + list[2].int };
                        },
                        else => error.UnsupportedOperation,
                    };
                },
                else => error.UnsupportedValue,
            };
        },
        else => error.UnsupportedValue,
    };
}

test "evaluates integers" {
    const cases = [_]struct {
        input: Value,
        expected: Value,
    }{
        .{
            .input = .{ .int = 42 },
            .expected = .{ .int = 42 },
        },
        .{
            .input = .{ .int = -7 },
            .expected = .{ .int = -7 },
        },
        .{
            .input = .{ .int = 0 },
            .expected = .{ .int = 0 },
        },
    };

    for (cases) |case| {
        const result = eval(case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "evaluates strings as themselves" {
    const cases = [_]struct {
        input: Value,
        expected: Value,
    }{
        .{
            .input = .{ .str = "\"hello\"" },
            .expected = .{ .str = "\"hello\"" },
        },
        .{
            .input = .{ .str = "" },
            .expected = .{ .str = "" },
        },
        .{
            .input = .{ .str = "line\\\nbreak" },
            .expected = .{ .str = "line\\\nbreak" },
        },
    };

    for (cases) |case| {
        const result = eval(case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "evaluates a basic builtin arithmetic call" {
    const input: Value = .{
        .list = &.{
            .{ .sym = "+" },
            .{ .int = 1 },
            .{ .int = 2 },
        },
    };
    const expected: Value = .{ .int = 3 };
    const result = eval(input);
    try std.testing.expectEqualDeep(expected, result);
}
