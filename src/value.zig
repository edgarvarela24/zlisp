pub const Value = union(enum) {
    int: i32,
    list: []const Value,
    sym: []const u8,
    str: []const u8,
};
