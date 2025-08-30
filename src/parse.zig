const std = @import("std");
const Allocator = std.mem.Allocator;

const JsonValue = @import("type.zig").JsonValue;

pub const ParseError = error{ UnterminatedString, SyntaxError, OutOfMemory, UnexpectedCharacter, InvalidComment };

pub const ValueRange = struct { start: usize, end: usize };

pub const PositionMap = std.AutoHashMap(usize, ValueRange);
pub const CommentRanges = std.ArrayList(ValueRange);

pub const JsonParser = struct {
    json_str: []const u8,
    idx: usize,
    positions: PositionMap,
    /// Store each comment's offset
    comment_ranges: CommentRanges,

    /// value_id is used as key for searching JsonValue ranges from PositionMap
    value_id: usize,

    const Self = @This();

    pub fn init(allocator: Allocator, json_str: []const u8) !Self {
        const comment_ranges = try std.ArrayList(ValueRange).initCapacity(allocator, 0);
        errdefer comment_ranges.deinit(allocator);

        const positions = std.AutoHashMap(usize, ValueRange).init(allocator);
        errdefer positions.deinit();

        return .{
            .json_str = json_str,
            .idx = 0,
            .positions = positions,
            .comment_ranges = comment_ranges,
            .value_id = 0,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.comment_ranges.deinit(allocator);
        self.positions.deinit();
    }

    pub fn parse(self: *Self, allocator: Allocator) ParseError!JsonValue {
        while (self.idx < self.json_str.len) : (self.idx += 1) {
            const char = self.getChar(self.idx) orelse continue;
            switch (char) {
                'n' => return self.parseLiteral("null"),
                't' => return self.parseLiteral("true"),
                'f' => return self.parseLiteral("false"),
                '"' => {
                    const value_id = self.generateId();
                    const start = self.idx;
                    const string = try self.parseString(allocator);
                    const end = self.idx;
                    try self.positions.put(value_id, .{ .start = start, .end = end });

                    return JsonValue{ .string = .{ .value = string, .id = value_id } };
                },
                '[' => return self.parseArray(allocator),
                '{' => return self.parseObject(allocator),
                '0'...'9', '-', 'e', '.' => return try self.parseNumber(allocator),
                '\n' => {},
                else => return ParseError.UnexpectedCharacter,
            }
        }
        return error.SyntaxError;
    }

    fn parseLiteral(self: *Self, expected_text: []const u8) ParseError!JsonValue {
        const value_id = self.generateId();
        const start = self.idx;

        if (self.idx + expected_text.len > self.json_str.len) {
            return ParseError.SyntaxError;
        }

        const slice = self.json_str[self.idx .. self.idx + expected_text.len];
        if (!std.mem.eql(u8, slice, expected_text)) {
            return ParseError.SyntaxError;
        }

        self.idx += expected_text.len - 1;
        const end = self.idx;

        try self.positions.put(value_id, .{
            .start = start,
            .end = end,
        });

        if (std.mem.eql(u8, expected_text, "null")) {
            return JsonValue{ .null = .{ .id = value_id } };
        } else if (std.mem.eql(u8, expected_text, "true")) {
            return JsonValue{ .bool = .{ .value = true, .id = value_id } };
        } else if (std.mem.eql(u8, expected_text, "false")) {
            return JsonValue{ .bool = .{ .value = false, .id = value_id } };
        } else {
            return ParseError.SyntaxError;
        }
    }

    fn parseString(self: *Self, allocator: Allocator) ParseError!std.ArrayList(u8) {
        var list = try std.ArrayList(u8).initCapacity(allocator, 10);
        // Skip the opening quote
        self.idx += 1;

        while (true) : (self.idx += 1) {
            const char = self.getChar(self.idx) orelse {
                break;
            };
            if (char == '"') {
                // Found closing quote
                return list;
            } else {
                try list.append(allocator, char);
            }
        }

        // String was not properly terminated with closing quote at index
        return ParseError.UnterminatedString;
    }

    fn parseNumber(self: *Self, allocator: Allocator) ParseError!JsonValue {
        const value_id = self.generateId();
        const start = self.idx;

        var bytes = try std.ArrayList(u8).initCapacity(allocator, 10);
        defer bytes.deinit(allocator);

        var has_dot = false;
        var has_e = false;

        while (self.idx < self.json_str.len) : (self.idx += 1) {
            switch (self.getChar(self.idx) orelse {
                break;
            }) {
                '0'...'9' => |digit| {
                    try bytes.append(allocator, digit);
                },
                '-' => |minus| {
                    if (bytes.items.len == 0 or
                        (bytes.items.len > 0 and (bytes.items[bytes.items.len - 1] == 'e' or bytes.items[bytes.items.len - 1] == 'E')))
                    {
                        try bytes.append(allocator, minus);
                    } else {
                        break;
                    }
                },
                '.' => |dot| {
                    if (!has_dot and !has_e) {
                        has_dot = true;
                        try bytes.append(allocator, dot);
                    } else {
                        break;
                    }
                },
                'e', 'E' => |e| {
                    if (!has_e and bytes.items.len > 0) {
                        has_e = true;
                        try bytes.append(allocator, e);
                    } else {
                        break;
                    }
                },
                '+' => |plus| {
                    // Only allow plus after 'e'/'E'
                    if (bytes.items.len > 0 and (bytes.items[bytes.items.len - 1] == 'e' or bytes.items[bytes.items.len - 1] == 'E')) {
                        try bytes.append(allocator, plus);
                    } else {
                        break;
                    }
                },
                else => {
                    break;
                },
            }
        }

        if (bytes.items.len == 0) return ParseError.SyntaxError;
        self.idx = start + bytes.items.len - 1;

        if (has_dot or has_e) {
            const float_val = std.fmt.parseFloat(f64, bytes.items) catch {
                return ParseError.SyntaxError;
            };
            const end = self.idx;
            try self.positions.put(value_id, .{
                .start = start,
                .end = end,
            });
            return JsonValue{ .float = .{ .value = float_val, .id = value_id } };
        } else {
            const int_val = std.fmt.parseInt(i64, bytes.items, 10) catch {
                return ParseError.SyntaxError;
            };
            const end = self.idx;
            try self.positions.put(value_id, .{
                .start = start,
                .end = end,
            });
            return JsonValue{ .integer = .{ .value = int_val, .id = value_id } };
        }
    }

    fn parseArray(self: *Self, allocator: Allocator) ParseError!JsonValue {
        const value_id = self.generateId();
        const start = self.idx;

        var array = try std.ArrayList(JsonValue).initCapacity(allocator, 10);

        self.idx += 1; // Skip opening bracket

        var commma = true;
        while (self.idx < self.json_str.len) : (self.idx += 1) {
            const char = self.getChar(self.idx) orelse {
                break;
            };
            if (char == ']') {
                // Found closing quote
                const end = self.idx;
                try self.positions.put(value_id, .{
                    .start = start,
                    .end = end,
                });
                return JsonValue{ .array = .{ .value = array, .id = value_id } };
            } else if (char == ' ' or char == '\n') {
                try self.skipWhiteAndComments(allocator);
                self.idx -= 1;
            } else if (char == ',') {
                if (commma) return error.SyntaxError;
                commma = true;
                self.idx += 1;
                try self.skipWhiteAndComments(allocator);
                self.idx -= 1;
            } else {
                if (commma) {
                    const parsed = try self.parse(allocator);
                    try array.append(allocator, parsed);
                    commma = false;
                }
            }
        }

        return ParseError.SyntaxError;
    }

    fn parseObject(self: *Self, allocator: Allocator) ParseError!JsonValue {
        const value_id = self.generateId();
        const start = self.idx;
        self.idx += 1; // Skip opening carly bracket

        var object = std.StringArrayHashMap(JsonValue).init(allocator);
        errdefer object.deinit();

        while (true) {
            try self.skipWhiteAndComments(allocator);
            var key = try self.parseString(allocator);
            self.idx += 1; // Skip last '"' of the key string
            try self.skipWhiteAndComments(allocator);

            if (self.getChar(self.idx) != ':') return error.SyntaxError;

            self.idx += 1;
            try self.skipWhiteAndComments(allocator);

            const value = try self.parse(allocator);

            try object.put(try key.toOwnedSlice(allocator), value);

            self.idx += 1;
            try self.skipWhiteAndComments(allocator);

            if (self.getChar(self.idx) == ',') {
                self.idx += 1;
                continue;
            }

            if (self.getChar(self.idx) == '}') break;
        }

        const end = self.idx;
        try self.positions.put(value_id, .{
            .start = start,
            .end = end,
        });
        return JsonValue{ .object = .{ .value = object, .id = value_id } };
    }

    // Stop at next to last space
    fn skipWhiteAndComments(self: *Self, allocator: Allocator) !void {
        while (true) : (self.idx += 1) {
            const char = self.getChar(self.idx) orelse break;
            if (char == ' ' or char == '\n') {
                continue;
            } else if (char == '/') {
                const comment = try self.parseComment() orelse continue;
                try self.comment_ranges.append(allocator, comment);
            } else {
                break;
            }
        }
    }

    fn skipWhite(self: *Self) !void {
        while (true) : (self.idx += 1) {
            const char = self.getChar(self.idx) orelse break;
            if (char == ' ') {
                continue;
            } else {
                break;
            }
        }
    }

    /// Parse comments
    fn parseComment(self: *Self) !?ValueRange {
        self.idx += 1;
        var char: u8 = self.getChar(self.idx) orelse return null;
        if (char != '/' and char != '*') return error.InvalidComment;
        self.idx += 1;
        try self.skipWhite();

        const start = self.idx; // Keep start offset of this comment

        // If starts with /*, it should be end with */
        const is_multiline = blk: {
            if (char == '*') break :blk true;
            break :blk false;
        };

        self.idx += 1;

        while (true) : (self.idx += 1) {
            char = self.getChar(self.idx) orelse {
                if (is_multiline) return error.SyntaxError;
                return ValueRange{
                    .start = start,
                    .end = self.idx,
                };
            };

            if (char == '\n') {
                if (is_multiline) continue;
                return ValueRange{
                    .start = start,
                    .end = self.idx - 1,
                };
            } else if (char == '*') {
                self.idx += 1;
                char = self.getChar(self.idx) orelse return error.InvalidComment;
                if (char == '/') {
                    return ValueRange{
                        .start = start,
                        .end = self.idx - 2,
                    };
                } else {
                    return error.InvalidComment;
                }
            }
        }
    }

    fn getChar(self: Self, position: usize) ?u8 {
        if (position >= self.json_str.len) return null;
        return self.json_str[position];
    }

    /// Assign unique ID to JsonValue
    fn generateId(self: *Self) usize {
        const id = self.value_id;
        self.value_id += 1;
        return id;
    }

    /// Returns value ranges in original input
    fn getValueRange(self: Self, value_id: usize) ?ValueRange {
        return self.positions.get(value_id);
    }
};

const testing = std.testing;

test "Parse null" {
    const input = "null";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .null);
}

test "Parse true" {
    const input = "true";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .bool);
    try testing.expect(parsed.bool.value == true);

    const parsed_id = parsed.bool.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(3, position.end);
}

test "Parse false" {
    const input = "false";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .bool);
    try testing.expect(parsed.bool.value == false);

    const parsed_id = parsed.bool.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(4, position.end);
}

test "Parse string" {
    const input = "\"Hello world\"";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .string);
    try testing.expectEqualStrings("Hello world", parsed.string.value.items);

    const parsed_id = parsed.string.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(12, position.end);
}

test "Parse integer" {
    const input = "123";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .integer);
    try testing.expectEqual(parsed.integer.value, 123);

    const parsed_id = parsed.integer.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(2, position.end);
}

test "Parse negative integer" {
    const input = "-45";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .integer);
    try testing.expectEqual(parsed.integer.value, -45);

    const parsed_id = parsed.integer.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(2, position.end);
}

test "Parse fraction" {
    const input = "14.1";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .float);
    try testing.expectEqual(parsed.float.value, 14.1);

    const parsed_id = parsed.float.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(3, position.end);
}

test "Parse exponential plus" {
    const input = "1.23e+4";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .float);
    try testing.expectEqual(parsed.float.value, 1.23e+4);

    const parsed_id = parsed.float.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(6, position.end);
}

test "Parse exponential negative" {
    const input = "1.23e-4";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .float);
    try testing.expectEqual(parsed.float.value, 1.23e-4);

    const parsed_id = parsed.float.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(6, position.end);
}

test "Parse array" {
    const input = "[1, 2, 3]";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .array);
    try testing.expect(parsed.array.value.items.len == 3);
    try testing.expect(parsed.array.value.items[0].integer.value == 1);
    try testing.expect(parsed.array.value.items[1].integer.value == 2);
    try testing.expect(parsed.array.value.items[2].integer.value == 3);

    const parsed_id = parsed.array.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(8, position.end);
}

test "Parse object" {
    const input =
        \\{
        \\  "lang": "zig",
        \\  "version" : 0.14
        \\}
    ;
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .object);
    try testing.expectEqualStrings("zig", parsed.object.value.get("lang").?.string.value.items);
    try testing.expectEqual(0.14, parsed.object.value.get("version").?.float.value);

    const parsed_id = parsed.object.id;
    const position = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, position.start);
    try testing.expectEqual(38, position.end);
}

test "Parse object of jsonc style" {
    const input = "{\n" ++
        "  \"lang\": \"zig\", // programming language\n" ++
        "  \"version\" : 0.14\n" ++
        "}";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .object);
    try testing.expectEqualStrings("zig", parsed.object.value.get("lang").?.string.value.items);
    try testing.expectEqual(0.14, parsed.object.value.get("version").?.float.value);

    // Verify comment ranges
    const comment_range = parser.comment_ranges.items[0];
    const comment = parser.json_str[comment_range.start .. comment_range.end + 1];
    try testing.expectEqualStrings("programming language", comment);

    // Verify Root object ranges
    const parsed_id = parsed.object.id;
    const parsed_range = parser.getValueRange(parsed_id).?;

    try testing.expectEqual(0, parsed_range.start);
    try testing.expectEqual(62, parsed_range.end);

    // Verify ranges of values of the root object
    const lang_value_range = parser.getValueRange(parsed.object.value.get("lang").?.string.id).?;
    const lang_value = parser.json_str[lang_value_range.start .. lang_value_range.end + 1];
    try testing.expectEqualStrings("\"zig\"", lang_value);

    const version_value_range = parser.getValueRange(parsed.object.value.get("version").?.float.id).?;
    const version_value = parser.json_str[version_value_range.start .. version_value_range.end + 1];
    try testing.expectEqualStrings("0.14", version_value);
}

test "Parse object with multi-line comment" {
    const input = "{\n" ++
        "  /*\n" ++
        "  multi-line\n" ++
        "   comments\n" ++
        "   */\n" ++
        "  \"lang\": \"zig\",\n" ++
        "  \"version\" : 0.14\n" ++
        "}";
    const allocator = testing.allocator;

    var parser = try JsonParser.init(allocator, input);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    try testing.expect(parsed == .object);
    // Verify ranges of values of the root object
    const lang_value_range = parser.getValueRange(parsed.object.value.get("lang").?.string.id).?;
    const lang_value = parser.json_str[lang_value_range.start .. lang_value_range.end + 1];
    try testing.expectEqualStrings("\"zig\"", lang_value);

    const version_value_range = parser.getValueRange(parsed.object.value.get("version").?.float.id).?;
    const version_value = parser.json_str[version_value_range.start .. version_value_range.end + 1];
    try testing.expectEqualStrings("0.14", version_value);

    const comment_range = parser.comment_ranges.items[0];
    const comment = parser.json_str[comment_range.start .. comment_range.end + 1];
    try testing.expectEqualStrings("\n  multi-line\n   comments\n   ", comment);
}
