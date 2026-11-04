const std = @import("std");
const Io = std.Io;

const zlisp = @import("zlisp");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) return error.ExpectedExpression;

    const builtins = try zlisp.builtins.init(arena);

    const lisp = args[1];

    const value = try zlisp.read(arena, lisp);

    const result = try zlisp.eval(arena, &builtins, value);

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try zlisp.print(stdout_writer, result);
    try stdout_writer.writeByte('\n');

    try stdout_writer.flush();
}
