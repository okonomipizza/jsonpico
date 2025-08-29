const std = @import("std");

pub const JsonError = error{OutOfMemory};

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

    pub fn deinit(self: *JsonValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .object => {
                var it = self.object.iterator();
                while (it.next()) |entry| {
                    self.object.allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                self.object.deinit();
            },
            .array => |*arr| {
                for (arr.items) |*item| {
                    switch (item.*) {
                        .object => item.deinit(allocator),
                        .string, .array => item.deinit(allocator),
                        else => {},
                    }
                }
                self.array.deinit(allocator);
            },
            .string => {
                self.string.deinit(allocator);
            },
            else => {},
        }
    }

    pub fn Stringify(self: @This(), allocator: std.mem.Allocator, writer: anytype) JsonError!void {
        switch (self) {
            .null => {
                try writer.writeAll("null");
            },
            .integer => |v| {
                try writer.print("{d}", .{v});
            },
            .float => |v| {
                try writer.print("{d}", .{v});
            },
            .bool => {
                try writer.writeAll(if (self.bool) "true" else "false");
            },
            .string => |v| {
                try writer.print("\"{s}\"", .{v.items});
            },
            .object => |v| {
                try writer.writeByte('{');
                for (v.keys(), 0..) |key, i| {
                    if (i > 0) try writer.writeAll(", ");
                    var bytes = try std.ArrayList(u8).initCapacity(allocator, key.len);
                    defer bytes.deinit(allocator);

                    try bytes.writer(allocator).writeAll(key);
                    try (JsonValue{ .string = bytes }).Stringify(allocator, writer);
                    try writer.writeAll(": ");
                    try v.get(key).?.Stringify(allocator, writer);
                }
                try writer.writeByte('}');
            },
            .array => |v| {
                try writer.writeByte('[');
                for (v.items, 0..) |value, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try value.Stringify(allocator, writer);
                }
                try writer.writeByte(']');
            },
        }
    }

    pub fn createString(allocator: std.mem.Allocator, str: []const u8) !JsonValue {
        var string_list = try std.ArrayList(u8).initCapacity(allocator, str.len);
        errdefer string_list.deinit(allocator);
        try string_list.appendSlice(allocator, str);
        return JsonValue{ .string = string_list };
    }

    pub fn createObject(allocator: std.mem.Allocator) JsonValue {
        return JsonValue{ .object = std.StringArrayHashMap(JsonValue).init(allocator) };
    }

    pub fn createArray(allocator: std.mem.Allocator) !JsonValue {
        return JsonValue{ .array = try std.ArrayList(JsonValue).initCapacity(allocator, 10) };
    }
};

const testing = std.testing;

test "Stringify null" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    const json_null = JsonValue{ .null = {} };
    try json_null.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("null", buffer.items);
}

test "Stringify bool" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    const json_null = JsonValue{ .bool = true };
    try json_null.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("true", buffer.items);
}

test "Stringify integer" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    const json_null = JsonValue{ .integer = 100 };
    try json_null.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("100", buffer.items);
}

test "Stringify float" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    const json_null = JsonValue{ .float = 1.2 };
    try json_null.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("1.2", buffer.items);
}

test "Stringify string" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    var json_string = try JsonValue.createString(allocator, "hello world");
    defer json_string.deinit(allocator);

    try json_string.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("\"hello world\"", buffer.items);
}

test "Stringify object" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    var json_object = JsonValue.createObject(allocator);
    defer json_object.deinit(allocator);

    const key1 = try testing.allocator.dupe(u8, "lang");
    const key2 = try testing.allocator.dupe(u8, "version");

    const value1 = try JsonValue.createString(allocator, "zig");
    try json_object.object.put(key1, value1);
    try json_object.object.put(key2, JsonValue{ .float = 0.14 });

    try json_object.Stringify(allocator, buffer.writer(allocator));

    const result = buffer.items;
    const expected = "{\"lang\": \"zig\", \"version\": 0.14}";

    try json_object.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings(expected, result);
}

test "Stringify array" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    var json_array = try JsonValue.createArray(allocator);
    defer json_array.deinit(allocator);

    try json_array.array.append(allocator, JsonValue{ .integer = 1 });
    try json_array.array.append(allocator, JsonValue{ .integer = 2 });
    try json_array.array.append(allocator, JsonValue{ .null = {} });

    try json_array.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("[1, 2, null]", buffer.items);
}
