const std = @import("std");
const Value = @import("value.zig").Value;

const Reader = struct {
    input: []const u8,
    allocator: std.mem.Allocator,
    cursor: usize,

    fn skipWhitespace(self: *Reader) void {
        while (self.cursor < self.input.len and std.ascii.isWhitespace(self.input[self.cursor])) : (self.cursor += 1) {}
    }

    fn readOne(self: *Reader) anyerror!Value {
        self.skipWhitespace();

        if (self.cursor == self.input.len) {
            return error.UnexpectedEndOfInput;
        }

        return try switch (self.input[self.cursor]) {
            ')' => error.UnexpectedClosingParen,
            '(' => self.readList(),
            '"' => self.readString(),
            else => self.readAtom(),
        };
    }

    fn readString(self: *Reader) !Value {
        var elements: std.ArrayList(u8) = .empty;
        defer elements.deinit(self.allocator);

        self.cursor += 1;

        while (self.cursor < self.input.len) : (self.cursor += 1) {
            if (self.input[self.cursor] == '\\') {
                self.cursor += 1;
                if (self.cursor == self.input.len) {
                    break;
                }
                const escaped = self.input[self.cursor];
                const decoded: u8 = switch (escaped) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    else => escaped,
                };
                try elements.append(self.allocator, decoded);
                continue;
            }
            if (self.input[self.cursor] == '"') {
                self.cursor += 1;
                const contents = try elements.toOwnedSlice(self.allocator);
                return .{ .str = contents };
            }
            try elements.append(self.allocator, self.input[self.cursor]);
        }

        return error.UnexpectedEndOfInput;
    }

    fn readAtom(self: *Reader) !Value {
        const start = self.cursor;

        const leading_sign = self.input[start] == '-' or self.input[start] == '+';
        var is_number = leading_sign or std.ascii.isDigit(self.input[start]);

        while (true) : (self.cursor += 1) {
            if (self.cursor == self.input.len or std.ascii.isWhitespace(self.input[self.cursor]) or self.input[self.cursor] == '(' or self.input[self.cursor] == ')' or self.input[self.cursor] == '"') {
                const atom = self.input[start..self.cursor];

                if (leading_sign and atom.len == 1) {
                    is_number = false;
                }

                if (is_number) {
                    const int = try std.fmt.parseInt(i32, atom, 10);
                    return .{ .int = int };
                }
                return .{ .sym = try self.allocator.dupe(u8, atom) };
            }

            if (self.cursor != start and !std.ascii.isDigit(self.input[self.cursor])) {
                is_number = false;
            }
        }
    }

    fn readList(self: *Reader) !Value {
        self.cursor += 1;
        var elements: std.ArrayList(Value) = .empty;
        defer elements.deinit(self.allocator);

        while (true) {
            self.skipWhitespace();

            if (self.cursor == self.input.len) {
                return error.UnexpectedEndOfInput;
            }

            const byte = self.input[self.cursor];

            if (byte == ')') {
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

/// Reads exactly one value with optional surrounding whitespace.
/// The result does not borrow from `input`.
///
/// Expects an arena allocator. Returned storage remains valid until the arena
/// is reset or destroyed, which also reclaims allocations made before errors.
pub fn read(allocator: std.mem.Allocator, input: []const u8) !Value {
    const trimmed = std.mem.trim(u8, input, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        return error.EmptyInput;
    }

    var reader = Reader{
        .input = input,
        .allocator = allocator,
        .cursor = 0,
    };

    const value = try reader.readOne();
    const remaining = reader.input[reader.cursor..];

    for (remaining) |byte| {
        if (byte == ')') {
            return error.UnexpectedClosingParen;
        }
        if (!std.ascii.isWhitespace(byte)) {
            return error.TrailingInput;
        }
    }

    return value;
}

test "read returns an integer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = [_]struct {
        input: []const u8,
        expected: Value,
    }{
        .{
            .input = "42",
            .expected = .{ .int = 42 },
        },
        .{
            .input = "-42",
            .expected = .{ .int = -42 },
        },
        .{
            .input = "0",
            .expected = .{ .int = 0 },
        },
    };

    for (cases) |case| {
        const result = try read(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "read treats double quotes as atom boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = [_]struct {
        input: []const u8,
        expected: Value,
    }{
        .{
            .input = "(hello\"world\")",
            .expected = .{
                .list = &.{
                    .{ .sym = "hello" },
                    .{ .str = "world" },
                },
            },
        },
        .{
            .input = "(42\"x\")",
            .expected = .{
                .list = &.{
                    .{ .int = 42 },
                    .{ .str = "x" },
                },
            },
        },
    };

    for (cases) |case| {
        const result = try read(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "read returns a symbol" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = [_]struct {
        input: []const u8,
        expected: Value,
    }{
        .{
            .input = "hello",
            .expected = .{ .sym = "hello" },
        },
        .{
            .input = "world",
            .expected = .{ .sym = "world" },
        },
        .{
            .input = "  hello  ",
            .expected = .{ .sym = "hello" },
        },
        .{
            .input = "he2llo",
            .expected = .{ .sym = "he2llo" },
        },
        .{
            .input = "+",
            .expected = .{ .sym = "+" },
        },
        .{
            .input = "-",
            .expected = .{ .sym = "-" },
        },
        .{
            .input = "*",
            .expected = .{ .sym = "*" },
        },
    };

    for (cases) |case| {
        const result = try read(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "read returns a list with elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = [_]struct {
        input: []const u8,
        expected: Value,
    }{
        .{
            .input = "()",
            .expected = .{
                .list = &.{},
            },
        },
        .{
            .input = "(  )",
            .expected = .{
                .list = &.{},
            },
        },
        .{
            .input = "   ()   ",
            .expected = .{
                .list = &.{},
            },
        },
        .{
            .input = "(42)",
            .expected = .{
                .list = &.{
                    .{ .int = 42 },
                },
            },
        },
        .{
            .input = "(42 7)",
            .expected = .{ .list = &.{
                .{ .int = 42 },
                .{ .int = 7 },
            } },
        },
        .{
            .input = "(42 7 -1)",
            .expected = .{
                .list = &.{
                    .{ .int = 42 },
                    .{ .int = 7 },
                    .{ .int = -1 },
                },
            },
        },
    };

    for (cases) |case| {
        const result = try read(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "read returns a list of symbols" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = [_]struct {
        input: []const u8,
        expected: Value,
    }{
        .{
            .input = "(hello world)",
            .expected = .{
                .list = &.{
                    .{ .sym = "hello" },
                    .{ .sym = "world" },
                },
            },
        },
        .{
            .input = "(+ x y)",
            .expected = .{
                .list = &.{
                    .{ .sym = "+" },
                    .{ .sym = "x" },
                    .{ .sym = "y" },
                },
            },
        },
    };

    for (cases) |case| {
        const result = try read(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "read returns a list of mixed values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cases = [_]struct {
        input: []const u8,
        expected: Value,
    }{
        .{
            .input = "(hello 69 world)",
            .expected = .{
                .list = &.{
                    .{ .sym = "hello" },
                    .{ .int = 69 },
                    .{ .sym = "world" },
                },
            },
        },
        .{
            .input = "(+ 1 2)",
            .expected = .{
                .list = &.{
                    .{ .sym = "+" },
                    .{ .int = 1 },
                    .{ .int = 2 },
                },
            },
        },
        .{
            .input = "(42 (7 8))",
            .expected = .{
                .list = &.{
                    .{ .int = 42 },
                    .{
                        .list = &.{
                            .{ .int = 7 },
                            .{ .int = 8 },
                        },
                    },
                },
            },
        },
        .{
            .input = "(* 2 3)",
            .expected = .{
                .list = &.{
                    .{ .sym = "*" },
                    .{ .int = 2 },
                    .{ .int = 3 },
                },
            },
        },
    };

    for (cases) |case| {
        const result = try read(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
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
    const cases = [_]struct {
        input: []const u8,
        expected: anyerror,
    }{
        .{ .input = "2147483648", .expected = error.Overflow },
        .{ .input = "", .expected = error.EmptyInput },
        .{ .input = "(", .expected = error.UnexpectedEndOfInput },
        .{ .input = "(42", .expected = error.UnexpectedEndOfInput },
        .{ .input = "((42)", .expected = error.UnexpectedEndOfInput },
        .{ .input = "(42 \t\n", .expected = error.UnexpectedEndOfInput },
    };

    for (cases) |case| {
        try std.testing.expectError(case.expected, read(allocator, case.input));
    }
}

test "read rejects whitespace-only input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = [_]struct { input: []const u8 }{
        .{ .input = " " },
        .{ .input = "\t\n" },
        .{ .input = " \t\r\n " },
    };

    for (cases) |case| {
        try std.testing.expectError(error.EmptyInput, read(allocator, case.input));
    }
}

test "read rejects unexpected closing parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = [_]struct {
        input: []const u8,
    }{
        .{ .input = ")" },
        .{ .input = ")(" },
        .{ .input = "  )" },
    };

    for (cases) |case| {
        try std.testing.expectError(error.UnexpectedClosingParen, read(allocator, case.input));
    }
}

test "read rejects extra closing parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = [_]struct {
        input: []const u8,
    }{
        .{ .input = "(42))" },
        .{ .input = "(42) )" },
        .{ .input = "42)" },
        .{ .input = "((42)))" },
    };

    for (cases) |case| {
        try std.testing.expectError(error.UnexpectedClosingParen, read(allocator, case.input));
    }
}

test "read rejects trailing values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = [_]struct {
        input: []const u8,
    }{
        .{ .input = "42 7" },
        .{ .input = "(42) 7" },
        .{ .input = "(42) (7)" },
    };

    for (cases) |case| {
        try std.testing.expectError(error.TrailingInput, read(allocator, case.input));
    }
}

test "read rejects unfinished strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    try std.testing.expectError(error.UnexpectedEndOfInput, read(allocator, "\"unfinished"));
}

test "read returns a symbol independent of the input buffer" {
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

test "read returns a string independent of the input buffer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var input = "\"hello\"".*;
    const result = try read(allocator, &input);

    try std.testing.expectEqualStrings("hello", result.str);

    input[1] = 'j';

    try std.testing.expectEqualStrings("\"jello\"", &input);
    try std.testing.expectEqualStrings("hello", result.str);
}

test "read returns an error for unterminated escape sequence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    try std.testing.expectError(error.UnexpectedEndOfInput, read(allocator, "\"hello\\"));
}

test "read returns a string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = [_]struct {
        input: []const u8,
        expected: Value,
    }{
        .{
            .input = "\"\"",
            .expected = .{ .str = "" },
        },
        .{
            .input = "\"hello\"",
            .expected = .{ .str = "hello" },
        },
        .{
            .input = "\"hello world\"",
            .expected = .{ .str = "hello world" },
        },
        .{
            .input = "\"(hello)\"",
            .expected = .{ .str = "(hello)" },
        },
        .{
            .input = "(\"hello\" (42 \"world\"))",
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
        const result = try read(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}

test "read decodes string escape sequences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const cases = [_]struct {
        input: []const u8,
        expected: Value,
    }{
        .{
            .input = "\"hello \\\"world\\\"\"",
            .expected = .{ .str = "hello \"world\"" },
        },
        .{
            .input = "\"hello\\nworld\"",
            .expected = .{ .str = "hello\nworld" },
        },
        .{
            .input = "\"\\t\\thello world\"",
            .expected = .{ .str = "\t\thello world" },
        },
        .{
            .input = "\"hello world\\r\\r\"",
            .expected = .{ .str = "hello world\r\r" },
        },
        .{
            .input = "\"hello\\\\\"",
            .expected = .{ .str = "hello\\" },
        },
        .{
            .input = "\"hello\\\\nworld\"",
            .expected = .{ .str = "hello\\nworld" },
        },
    };

    for (cases) |case| {
        const result = try read(allocator, case.input);
        try std.testing.expectEqualDeep(case.expected, result);
    }
}
