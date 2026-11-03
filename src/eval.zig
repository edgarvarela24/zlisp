const std = @import("std");
const Value = @import("value.zig").Value;

const builtins = @import("builtins.zig");
const BuiltinMap = builtins.BuiltinMap;

const Evaluator = struct {
    input: Value,
    builtins: *const BuiltinMap,

    fn evaluate(self: *Evaluator) !Value {
        return switch (self.input) {
            .int => |int| .{ .int = int },
            .str => |str| .{ .str = str },
            .list => |list| {
                if (list.len == 0) {
                    return .{ .list = &.{} };
                }

                const first = list[0];
                return switch (first) {
                    .sym => |sym| {
                        const builtin = self.builtins.get(sym) orelse return error.UnsupportedOperation;
                        return builtin(list[1..]);
                    },
                    else => error.UnsupportedValue,
                };
            },
            else => error.UnsupportedValue,
        };
    }
};

pub fn eval(built_ins: *const BuiltinMap, value: Value) !Value {
    var evaluator = Evaluator{
        .input = value,
        .builtins = built_ins,
    };
    const result: Value = try evaluator.evaluate();
    return result;
}

test "evaluates integers" {
    var registry = try builtins.init(std.testing.allocator);
    defer registry.deinit();

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
        const result = eval(&registry, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "evaluates strings as themselves" {
    var registry = try builtins.init(std.testing.allocator);
    defer registry.deinit();

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
        const result = eval(&registry, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "evaluates a basic builtin arithmetic call" {
    var registry = try builtins.init(std.testing.allocator);
    defer registry.deinit();

    const input: Value = .{
        .list = &.{
            .{ .sym = "+" },
            .{ .int = 1 },
            .{ .int = 2 },
        },
    };
    const expected: Value = .{ .int = 3 };
    const result = eval(&registry, input);
    try std.testing.expectEqualDeep(expected, result);
}
