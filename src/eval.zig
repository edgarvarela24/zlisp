const std = @import("std");
const Value = @import("value.zig").Value;

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

const Evaluator = struct {
    input: Value,
    allocator: std.mem.Allocator,
    stdFns: std.StringHashMap(*const fn (args: []const Value) Value),

    pub fn init(allocator: std.mem.Allocator, input: Value) !Evaluator {
        var stdFns = std.StringHashMap(*const fn (args: []const Value) Value).init(allocator);

        try stdFns.put(
            "+",
            &add,
        );

        return Evaluator{
            .input = input,
            .allocator = allocator,
            .stdFns = stdFns,
        };
    }

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
                        const stdFn = self.stdFns.get(sym) orelse return error.UnsupportedOperation;
                        return stdFn(list[1..]);
                    },
                    else => error.UnsupportedValue,
                };
            },
            else => error.UnsupportedValue,
        };
    }
};

pub fn eval(allocator: std.mem.Allocator, value: Value) !Value {
    var evaluator = try Evaluator.init(allocator, value);

    const result: Value = try evaluator.evaluate();

    return result;
}

test "evaluates integers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

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
        const result = eval(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "evaluates strings as themselves" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

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
        const result = eval(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "evaluates a basic builtin arithmetic call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const input: Value = .{
        .list = &.{
            .{ .sym = "+" },
            .{ .int = 1 },
            .{ .int = 2 },
        },
    };
    const expected: Value = .{ .int = 3 };
    const result = eval(allocator, input);
    try std.testing.expectEqualDeep(expected, result);
}
