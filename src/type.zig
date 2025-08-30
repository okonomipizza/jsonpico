const std = @import("std");

pub const JsonError = error{OutOfMemory};

pub const JsonValue = union(enum) {
    /// 'null'.
    null: struct {
        id: usize,
    },

    /// Integer number.
    integer: struct { value: i64, id: usize },

    /// Floating point number.
    float: struct { value: f64, id: usize },

    /// 'true' or 'false'
    bool: struct { value: bool, id: usize },

    /// String.
    string: struct { value: std.ArrayList(u8), id: usize },

    /// Object.
    object: struct { value: std.StringArrayHashMap(JsonValue), id: usize },

    /// Array.
    array: struct { value: std.ArrayList(JsonValue), id: usize },

    pub fn getId(self: JsonValue) usize {
        return switch (self) {
            inline else => |payload| payload.id,
        };
    }

    pub fn deinit(self: *JsonValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .object => {
                var it = self.object.value.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                self.object.value.deinit();
            },
            .array => |*arr| {
                for (arr.value.items) |*item| {
                    item.deinit(allocator);
                }
                arr.value.deinit(allocator);
            },
            .string => |*str| {
                str.value.deinit(allocator);
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
                try writer.print("{d}", .{v.value});
            },
            .float => |v| {
                try writer.print("{d}", .{v.value});
            },
            .bool => {
                try writer.writeAll(if (self.bool.value) "true" else "false");
            },
            .string => |v| {
                try writer.print("\"{s}\"", .{v.value.items});
            },
            .object => |v| {
                try writer.writeByte('{');
                for (v.value.keys(), 0..) |key, i| {
                    if (i > 0) try writer.writeAll(", ");
                    var bytes = try std.ArrayList(u8).initCapacity(allocator, key.len);
                    defer bytes.deinit(allocator);

                    try bytes.writer(allocator).writeAll(key);
                    try (JsonValue{ .string = .{ .value = bytes, .id = 0 } }).Stringify(allocator, writer); // Temporary JsonValue for stringify only, ID not needed
                    try writer.writeAll(": ");
                    try v.value.get(key).?.Stringify(allocator, writer);
                }
                try writer.writeByte('}');
            },
            .array => |v| {
                try writer.writeByte('[');
                for (v.value.items, 0..) |value, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try value.Stringify(allocator, writer);
                }
                try writer.writeByte(']');
            },
        }
    }

    pub fn createString(allocator: std.mem.Allocator, str: []const u8, id: usize) !JsonValue {
        var string_list = try std.ArrayList(u8).initCapacity(allocator, str.len);
        errdefer string_list.deinit(allocator);
        try string_list.appendSlice(allocator, str);
        return JsonValue{ .string = .{ .value = string_list, .id = id } };
    }

    pub fn createObject(allocator: std.mem.Allocator, id: usize) JsonValue {
        return JsonValue{ .object = .{ .value = std.StringArrayHashMap(JsonValue).init(allocator), .id = id } };
    }

    pub fn createArray(allocator: std.mem.Allocator, id: usize) !JsonValue {
        return JsonValue{ .array = .{ .value = try std.ArrayList(JsonValue).initCapacity(allocator, 10), .id = id } };
    }
};

const testing = std.testing;

test "Stringify null" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    const json_null = JsonValue{ .null = .{ .id = 0 } };
    try json_null.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("null", buffer.items);
}

test "Stringify bool" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    const json_null = JsonValue{ .bool = .{ .value = true, .id = 0 } };
    try json_null.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("true", buffer.items);
}

test "Stringify integer" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    const json_null = JsonValue{ .integer = .{ .value = 100, .id = 0 } };
    try json_null.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("100", buffer.items);
}

test "Stringify float" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    const json_null = JsonValue{ .float = .{ .value = 1.2, .id = 0 } };
    try json_null.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("1.2", buffer.items);
}

test "Stringify string" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    var json_string = try JsonValue.createString(allocator, "hello world", 0);
    defer json_string.deinit(allocator);

    try json_string.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("\"hello world\"", buffer.items);
}

test "Stringify object" {
    const allocator = testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer buffer.deinit(allocator);

    var json_object = JsonValue.createObject(allocator, 0);
    defer json_object.deinit(allocator);

    const key1 = try testing.allocator.dupe(u8, "lang");
    const key2 = try testing.allocator.dupe(u8, "version");

    const value1 = try JsonValue.createString(allocator, "zig", 1);
    try json_object.object.value.put(key1, value1);
    try json_object.object.value.put(key2, JsonValue{ .float = .{ .value = 0.14, .id = 2 } });

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

    var json_array = try JsonValue.createArray(allocator, 0);
    defer json_array.deinit(allocator);

    try json_array.array.value.append(allocator, JsonValue{ .integer = .{ .value = 1, .id = 1 } });
    try json_array.array.value.append(allocator, JsonValue{ .integer = .{ .value = 2, .id = 2 } });
    try json_array.array.value.append(allocator, JsonValue{ .null = .{ .id = 3 } });

    try json_array.Stringify(allocator, buffer.writer(allocator));

    try testing.expectEqualStrings("[1, 2, null]", buffer.items);
}
