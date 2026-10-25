const std = @import("std");

const Value = union(enum) { int: i32, list: []const Value, sym: []const u8, str: []const u8 };

const Reader = struct {
    input: []const u8,
    allocator: std.mem.Allocator,
    cursor: usize,

    fn readOne(self: *Reader) anyerror!Value {
        if (self.input.len == 0) {
            return error.EmptyInput;
        }
        while (true) {
            const token = self.input[self.cursor];
            if (std.ascii.isWhitespace(token)) {
                self.cursor += 1;
            } else {
                break;
            }
        }
        if (self.input[self.cursor] == ')') {
            return error.UnexpectedClosingParen;
        }
        if (self.input[self.cursor] == '(') {
            return self.readList();
        }
        return self.readAtom();
    }

    fn readAtom(self: *Reader) !Value {
        var start = self.cursor;

        if (self.input[start] == '"') {
            self.cursor += 1;
            start += 1;
            var endQuote = false;
            var end = start;
            while (self.cursor < self.input.len) : (self.cursor += 1) {
                if (self.input[self.cursor] == '"') {
                    endQuote = true;
                    end = self.cursor;
                    self.cursor += 1;
                    break;
                }
            }
            if (endQuote) {
                return .{ .str = self.input[start..end] };
            } else {
                return error.UnexpectedEndOfInput;
            }
        }

        var is_sym = true;
        for (self.input[start..]) |token| {
            if (std.ascii.isWhitespace(token) or token == '(' or token == ')') {
                break;
            }
            self.cursor += 1;
            if (!std.ascii.isAlphabetic(token) and token != '+' and token != '-') {
                is_sym = false;
            }
        }

        const atom = self.input[start..self.cursor];

        if (is_sym) {
            return .{
                .sym = try self.allocator.dupe(u8, atom),
            };
        }

        const int = try std.fmt.parseInt(i32, atom, 10);
        return .{
            .int = int,
        };
    }

    fn readList(self: *Reader) !Value {
        self.cursor += 1;
        var elements: std.ArrayList(Value) = .empty;
        defer elements.deinit(self.allocator);

        while (true) {
            if (self.cursor == self.input.len) {
                return error.UnexpectedEndOfInput;
            }
            const token = self.input[self.cursor];
            if (std.ascii.isWhitespace(token)) {
                self.cursor += 1;
                continue;
            }
            if (token == ')') {
                self.cursor += 1;
                break;
            }
            const element = try self.readOne();
            try elements.append(self.allocator, element);
        }
        const slice = try elements.toOwnedSlice(self.allocator);

        return .{
            .list = slice,
        };
    }
};

/// read expects arena-managed storage for now. returned values remain valid until that
/// arena is reset or destroyed
pub fn read(allocator: std.mem.Allocator, val: []const u8) !Value {
    const trimmed = std.mem.trim(u8, val, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        return error.EmptyInput;
    }

    var reader = Reader{
        .input = val,
        .allocator = allocator,
        .cursor = 0,
    };

    const value = try reader.readOne();
    const remaining = reader.input[reader.cursor..];

    for (remaining) |token| {
        if (token == ')') {
            return error.UnexpectedClosingParen;
        }
        if (!std.ascii.isWhitespace(token)) {
            return error.TrailingInput;
        }
    }

    return value;
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
                .list => |list| {
                    try std.testing.expectEqualDeep(list, list_item.list);
                },
                .str => |string| {
                    std.debug.print("%s", .{string});
                },
            }
        }
    }
}

test "read returns a list beginning with a nested list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const expected: Value = .{ .list = &.{
        .{ .list = &.{.{ .int = 42 }} },
    } };
    const result = try read(arena.allocator(), "((42))");

    try std.testing.expectEqualDeep(expected, result);
}

test "read returns sibling nested lists without separating whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const expected: Value = .{ .list = &.{
        .{ .list = &.{.{ .int = 1 }} },
        .{ .list = &.{.{ .int = 2 }} },
    } };
    const result = try read(arena.allocator(), "((1)(2))");

    try std.testing.expectEqualDeep(expected, result);
}

test "read resumes the outer list after deeper nesting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const expected: Value = .{ .list = &.{
        .{ .int = 1 },
        .{ .list = &.{
            .{ .int = 2 },
            .{ .list = &.{.{ .int = 3 }} },
        } },
        .{ .int = 4 },
    } };
    const result = try read(arena.allocator(), "(1 (2 (3)) 4)");

    try std.testing.expectEqualDeep(expected, result);
}

test "read returns empty and nonempty nested lists together" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const expected: Value = .{ .list = &.{
        .{ .list = &.{} },
        .{ .list = &.{.{ .int = 42 }} },
        .{ .list = &.{} },
    } };
    const result = try read(arena.allocator(), "(() (42) ())");

    try std.testing.expectEqualDeep(expected, result);
}

test "read handles mixed values and whitespace across nesting levels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const expected: Value = .{ .list = &.{
        .{ .sym = "hello" },
        .{ .list = &.{
            .{ .int = 42 },
            .{ .list = &.{.{ .sym = "world" }} },
        } },
    } };
    const result = try read(arena.allocator(), " \t(hello\n (42\t(world)))\r\n");

    try std.testing.expectEqualDeep(expected, result);
}

test "read propagates integer overflow from a nested list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(
        error.Overflow,
        read(arena.allocator(), "(hello (2147483648))"),
    );
}

test "read reports error cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = .{
        .{ .val = "2147483648", .expected = error.Overflow },
        .{ .val = "he2llo", .expected = error.InvalidCharacter },
        .{ .val = "", .expected = error.EmptyInput },
        .{ .val = "(", .expected = error.UnexpectedEndOfInput },
        .{ .val = "(42", .expected = error.UnexpectedEndOfInput },
        .{ .val = "((42)", .expected = error.UnexpectedEndOfInput },
        .{ .val = "(42 \t\n", .expected = error.UnexpectedEndOfInput },
    };

    inline for (cases) |case| {
        try std.testing.expectError(case.expected, read(allocator, case.val));
    }
}

test "read rejects whitespace-only input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = .{
        " ",
        "\t\n",
        " \t\r\n ",
    };

    inline for (cases) |input| {
        try std.testing.expectError(error.EmptyInput, read(allocator, input));
    }
}

test "read rejects unexpected closing parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = .{ ")", ")(", "  )" };

    inline for (cases) |input| {
        try std.testing.expectError(error.UnexpectedClosingParen, read(allocator, input));
    }
}

test "read rejects extra closing parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = .{ "(42))", "(42) )", "42)", "((42)))" };

    inline for (cases) |input| {
        try std.testing.expectError(error.UnexpectedClosingParen, read(allocator, input));
    }
}

test "read rejects trailing values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = .{ "42 7", "(42) 7", "(42) (7)" };

    inline for (cases) |input| {
        try std.testing.expectError(error.TrailingInput, read(allocator, input));
    }
}

test "read rejects unfinished strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    try std.testing.expectError(error.UnexpectedEndOfInput, read(allocator, "\"unfinished"));
}

test "symbol retains ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var input = "hello".*;
    const result = try read(allocator, &input);

    try std.testing.expectEqualStrings("hello", result.sym);

    input[0] = 'j';

    try std.testing.expectEqualStrings("jello", &input);
    try std.testing.expectEqualStrings("hello", result.sym);
}

test "read returns a string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = [_]struct {
        val: []const u8,
        expected: Value,
    }{
        .{
            .val = "\"\"",
            .expected = .{ .str = "" },
        },
        .{
            .val = "\"hello\"",
            .expected = .{ .str = "hello" },
        },
        .{
            .val = "\"hello world\"",
            .expected = .{ .str = "hello world" },
        },
        .{
            .val = "\"(hello)\"",
            .expected = .{ .str = "(hello)" },
        },
        .{
            .val = "(\"hello\" (42 \"world\"))",
            .expected = .{ .list = &.{
                .{ .str = "hello" },
                .{
                    .list = &.{
                        .{ .int = 42 },
                        .{ .str = "world" },
                    },
                },
            } },
        },
    };

    for (cases) |case| {
        const result = try read(allocator, case.val);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}
