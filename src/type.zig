const std = @import("std");

pub const JsonValue = union(enum) {
    /// 'null'.
    null,

    /// Integer number.
    integer: i64,

    /// Floating point number.
    float: f64,

    /// 'true' or 'false'
    bool: bool,

    /// String.
    string: std.ArrayList(u8),

    /// Object.
    object: std.StringArrayHashMap(JsonValue),

    /// Array.
    array: std.ArrayList(JsonValue),

    pub fn deinit(self: *JsonValue) void {
        switch (self.*) {
            .object => {
                var it = self.object.iterator();
                while (it.next()) |entry| {
                    self.object.allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit();
                }
                self.object.deinit();
            },
            .array => {
                self.array.deinit();
            },
            .string => {
                self.string.deinit();
            },
            else => {},
        }
    }
};
