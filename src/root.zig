const reader = @import("reader.zig");
const printer = @import("printer.zig");

pub const read = reader.read;
pub const print = printer.print;

test {
    _ = printer;
    _ = reader;
}
