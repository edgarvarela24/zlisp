const std = @import("std");
const builtins = @import("builtins.zig");
const BuiltinMap = builtins.BuiltinMap;
const Value = @import("value.zig").Value;

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const evaluator = @import("eval.zig");

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    builtins: BuiltinMap,
    globals: std.StringHashMap(Value),

    pub fn read(self: *Runtime, input: []const u8) !Value {
        return reader.read(self.arena.allocator(), input);
    }

    pub fn eval(self: *Runtime, value: Value) !Value {
        return evaluator.eval(self.arena.allocator(), &self.builtins, value);
    }

    pub fn print(self: *Runtime, writer: *std.Io.Writer, value: Value) !void {
        _ = self;
        return printer.print(writer, value);
    }

    pub fn init(allocator: std.mem.Allocator) !Runtime {
        return Runtime{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .builtins = try builtins.init(allocator),
            .globals = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.globals.deinit();
        self.builtins.deinit();
        self.arena.deinit();
    }
};
