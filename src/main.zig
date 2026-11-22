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

    var runtime = try zlisp.Runtime.init(init.gpa);
    defer runtime.deinit();

    while (try stdin_reader.takeDelimiter('\n')) |line| {
        const value = runtime.read(line) catch |err| {
            std.log.err("Read failed: {s}", .{@errorName(err)});
            continue;
        };

        const result = runtime.eval(value) catch |err| {
            std.log.err("Evaluation failed: {s}", .{@errorName(err)});
            continue;
        };

        runtime.print(stdout_writer, result) catch |err| {
            std.log.err("Print failed: {s}", .{@errorName(err)});
            continue;
        };

        try stdout_writer.writeByte('\n');

        try stdout_writer.flush();
    }
}
