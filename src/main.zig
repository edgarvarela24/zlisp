const std = @import("std");
const Io = std.Io;

const zlisp = @import("zlisp");

pub fn main(init: std.process.Init) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_file_reader = Io.File.stdin().reader(init.io, &stdin_buffer);
    const stdin_reader = &stdin_file_reader.interface;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer = Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var builtins = try zlisp.builtins.init(init.gpa);
    defer builtins.deinit();

    while (try stdin_reader.takeDelimiter('\n')) |line| {
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();

        const allocator = arena.allocator();

        const value = zlisp.read(allocator, line) catch |err| {
            std.log.err("Read failed: {s}", .{@errorName(err)});
            continue;
        };

        const result = zlisp.eval(allocator, &builtins, value) catch |err| {
            std.log.err("Evaluation failed: {s}", .{@errorName(err)});
            continue;
        };

        zlisp.print(stdout_writer, result) catch |err| {
            std.log.err("Print failed: {s}", .{@errorName(err)});
            continue;
        };

        try stdout_writer.writeByte('\n');

        try stdout_writer.flush();
    }
}
