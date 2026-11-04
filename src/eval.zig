const std = @import("std");
const Value = @import("value.zig").Value;

const builtins = @import("builtins.zig");
const BuiltinMap = builtins.BuiltinMap;

pub const Error =
    std.mem.Allocator.Error ||
    builtins.Error ||
    error{UnsupportedOperation};

const Evaluator = struct {
    allocator: std.mem.Allocator,
    builtins: *const BuiltinMap,

    fn evaluate(self: *Evaluator, input: Value) Error!Value {
        return switch (input) {
            .int => |int| .{ .int = int },
            .str => |str| .{ .str = str },
            .list => |list| try self.evaluateList(list),
            else => error.UnsupportedValue,
        };
    }

    fn evaluateList(self: *Evaluator, list: []const Value) !Value {
        if (list.len == 0) {
            return .{ .list = &.{} };
        }

        const first = list[0];
        return switch (first) {
            .sym => |sym| {
                const builtin = self.builtins.get(sym) orelse return error.UnsupportedOperation;
                var args: std.ArrayList(Value) = .empty;
                defer args.deinit(self.allocator);

                for (list[1..]) |value| {
                    const arg = try self.evaluate(value);
                    try args.append(self.allocator, arg);
                }

                return builtin(args.items);
            },
            else => error.UnsupportedValue,
        };
    }
};

pub fn eval(allocator: std.mem.Allocator, built_ins: *const BuiltinMap, value: Value) !Value {
    var evaluator = Evaluator{
        .allocator = allocator,
        .builtins = built_ins,
    };
    const result: Value = try evaluator.evaluate(value);
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
        const result = eval(std.testing.allocator, &registry, case.input);
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
        const result = eval(std.testing.allocator, &registry, case.input);
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
    const result = eval(std.testing.allocator, &registry, input);
    try std.testing.expectEqualDeep(expected, result);
}

test "evaluates nested builtin calls" {
    var registry = try builtins.init(std.testing.allocator);
    defer registry.deinit();

    const input: Value = .{
        .list = &.{
            .{ .sym = "+" },
            .{ .int = 1 },
            .{
                .list = &.{
                    .{ .sym = "+" },
                    .{ .int = 2 },
                    .{ .int = 3 },
                },
            },
        },
    };
    const expected: Value = .{ .int = 6 };
    const result = try eval(std.testing.allocator, &registry, input);

    try std.testing.expectEqualDeep(expected, result);
}
