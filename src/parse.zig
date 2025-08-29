const std = @import("std");
const Allocator = std.mem.Allocator;

const JsonValue = @import("type.zig").JsonValue;

pub const ParseError = error{
    UnterminatedString,
    SyntaxError,
    OutOfMemory,
    UnexpectedCharacter,
    InvalidComment
};

pub const Comment = struct {
    start: usize,
    end: usize,
};

pub const JsonParser = struct {
    json_str: []const u8,
    idx: usize,
    /// Store each comment's offset
    comments: std.ArrayList(Comment),

    const Self = @This();

    pub fn init(allocator: Allocator, json_str: []const u8) Self {
        const comments = std.ArrayList(Comment).init(allocator);

        return .{
            .json_str = json_str,
            .idx = 0,
            .comments = comments,
        };
    }

    pub fn deinit(self: *Self) void {
       self.comments.deinit(); 
    }

    pub fn parse(self: *Self, allocator: Allocator) ParseError!JsonValue {
        while (self.idx < self.json_str.len) : (self.idx += 1) {
            const char = self.getChar(self.idx) orelse continue;
            switch (char) {
                'n' => return self.parseLiteral(.null, "null"),
                't' => return self.parseLiteral(.{ .bool = true }, "true"),
                'f' => return self.parseLiteral(.{ .bool = false }, "false"),
                '"' => {
                    const string = try self.parseString(allocator);
                    return JsonValue{ .string = string };
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

    fn parseLiteral(self: *Self, expected_value: JsonValue, expected_text: []const u8) ParseError!JsonValue {
        if (self.idx + expected_text.len > self.json_str.len) {
            return ParseError.SyntaxError;
        }

        const slice = self.json_str[self.idx .. self.idx + expected_text.len];
        if (!std.mem.eql(u8, slice, expected_text)) {
            return ParseError.SyntaxError;
        }

        self.idx += expected_text.len - 1;

        return expected_value;
    }

    fn parseString(self: *Self, allocator: Allocator) ParseError!std.ArrayList(u8) {
        var list = std.ArrayList(u8).init(allocator);

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
                try list.append(char);
            }
        }

        // String was not properly terminated with closing quote at index
        return ParseError.UnterminatedString;
    }

    fn parseNumber(self: *Self, allocator: Allocator) ParseError!JsonValue {
        var bytes = std.ArrayList(u8).init(allocator);
        defer bytes.deinit();

        var has_dot = false;
        var has_e = false;

        while (self.idx < self.json_str.len) : (self.idx += 1) {
            switch (self.getChar(self.idx) orelse break) {
                '0'...'9' => |digit| {
                    try bytes.append(digit);
                },
                '-' => |minus| {
                    if (bytes.items.len == 0 or
                        (bytes.items.len > 0 and (bytes.items[bytes.items.len - 1] == 'e' or bytes.items[bytes.items.len - 1] == 'E')))
                    {
                        try bytes.append(minus);
                    } else {
                        break;
                    }
                },
                '.' => |dot| {
                    if (!has_dot and !has_e) {
                        has_dot = true;
                        try bytes.append(dot);
                    } else {
                        break;
                    }
                },
                'e', 'E' => |e| {
                    if (!has_e and bytes.items.len > 0) {
                        has_e = true;
                        try bytes.append(e);
                    } else {
                        break;
                    }
                },
                '+' => |plus| {
                    // Only allow plus after 'e'/'E'
                    if (bytes.items.len > 0 and (bytes.items[bytes.items.len - 1] == 'e' or bytes.items[bytes.items.len - 1] == 'E')) {
                        try bytes.append(plus);
                    } else {
                        break;
                    }
                },
                else => {
                    self.idx -= 1;
                    break;
                },
            }
        }

        if (bytes.items.len == 0) return ParseError.SyntaxError;

        if (has_dot or has_e) {
            const float_val = std.fmt.parseFloat(f64, bytes.items) catch {
                return ParseError.SyntaxError;
            };
            return JsonValue{ .float = float_val };
        } else {
            const int_val = std.fmt.parseInt(i64, bytes.items, 10) catch {
                return ParseError.SyntaxError;
            };
            return JsonValue{ .integer = int_val };
        }
    }

    fn parseArray(self: *Self, allocator: Allocator) ParseError!JsonValue {
        var array = std.ArrayList(JsonValue).init(allocator);

        self.idx += 1; // Skip opening bracket

        var commma = true;
        while (self.idx < self.json_str.len) : (self.idx += 1) {
            const char = self.getChar(self.idx) orelse {
                break;
            };
            if (char == ']') {
                // Found closing quote
                return JsonValue{ .array = array };
            } else if (char == ' ' or char == '\n') {
                try  self.skipWhiteAndComments();
                self.idx -= 1;
            } else if (char == ',') {
                if (commma) return error.SyntaxError;
                commma = true;
                self.idx += 1;
                try self.skipWhiteAndComments();
                self.idx -= 1;
            } else {
                if (commma) {
                    const parsed = try self.parse(allocator);
                    try array.append(parsed);
                    commma = false;
                }
            }
        }

        return ParseError.SyntaxError;
    }

    fn parseObject(self: *Self, allocator: Allocator) ParseError!JsonValue {
        self.idx += 1; // Skip opening carly bracket

        var object = std.StringArrayHashMap(JsonValue).init(allocator);
        errdefer object.deinit();

        while (true) {
            try self.skipWhiteAndComments();
            var key = try self.parseString(allocator);
            self.idx += 1; // Skip last '"' of the key string
            try self.skipWhiteAndComments();

            if (self.getChar(self.idx) != ':') return error.SyntaxError;

            self.idx += 1;
            try self.skipWhiteAndComments();

            const value = try self.parse(allocator);

            try object.put(try key.toOwnedSlice(), value);

            self.idx += 1;
            try self.skipWhiteAndComments();

            if (self.getChar(self.idx) == ',') {
                self.idx += 1;
                continue;
            }

            if (self.getChar(self.idx) == '}') break;
        }

        return JsonValue{ .object = object };
    }

    // Stop at next to last space
    fn skipWhiteAndComments(self: *Self) !void {
        while (true) : (self.idx += 1) {
            const char = self.getChar(self.idx) orelse break;
            if (char == ' ' or char == '\n') {
                continue;
            } else if (char == '/') {
                const comment = try self.parseComment() orelse continue;
                try self.comments.append(comment);
            } else {
                break;
            }
        }
    }

    /// Parse comments
    fn parseComment(self: *Self) !?Comment {
        self.idx += 1;
        var char: u8 = self.getChar(self.idx) orelse return null;
        if (char != '/' and char != '*') return error.InvalidComment;
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
                return Comment{
                    .start = start,
                    .end = self.idx,
                };
            };
            
            if (char == '\n') {
                if (is_multiline) continue;
                return Comment{
                    .start = start,
                    .end = self.idx,
                };
            } else if (char == '*') {
                self.idx += 1;
                char = self.getChar(self.idx) orelse return error.InvalidComment;
                if (char == '/') {
                    return Comment{
                        .start = start,
                        .end = self.idx,
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
};

const testing = std.testing;

test "Parse null" {
    const input = "null";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .null);
}

test "Parse true" {
    const input = "true";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .bool);
    try testing.expect(parsed.bool == true);
}

test "Parse false" {
    const input = "false";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .bool);
    try testing.expect(parsed.bool == false);
}

test "Parse string" {
    const input = "\"Hello world\"";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .string);
    try testing.expectEqualStrings("Hello world", parsed.string.items);
}

test "Parse integer" {
    const input = "123";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .integer);
    try testing.expectEqual(parsed.integer, 123);
}

test "Parse negative integer" {
    const input = "-45";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .integer);
    try testing.expectEqual(parsed.integer, -45);
}

test "Parse fraction" {
    const input = "14.1";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .float);
    try testing.expectEqual(parsed.float, 14.1);
}
test "Parse exponential plus" {
    const input = "1.23e+4";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .float);
    try testing.expectEqual(parsed.float, 1.23e+4);
}

test "Parse exponential negative" {
    const input = "1.23e-4";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .float);
    try testing.expectEqual(parsed.float, 1.23e-4);
}

test "Parse array" {
    const input = "[1, 2, 3]";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .array);
    try testing.expect(parsed.array.items.len == 3);
    try testing.expect(parsed.array.items[0].integer == 1);
    try testing.expect(parsed.array.items[1].integer == 2);
    try testing.expect(parsed.array.items[2].integer == 3);
}

test "Parse object" {
    const input =
        \\{
        \\  "lang": "zig",
        \\  "version" : 0.14
        \\}
    ;
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .object);
    try testing.expectEqualStrings("zig", parsed.object.get("lang").?.string.items);
    try testing.expectEqual(0.14, parsed.object.get("version").?.float);
}

test "Parse object of jsonc style" {
    const input = "{\n" ++
        "  \"lang\": \"zig\", // programming language\n" ++
        "  \"version\" : 0.14\n" ++
        "}";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .object);
    try testing.expectEqualStrings("zig", parsed.object.get("lang").?.string.items);
    try testing.expectEqual(0.14, parsed.object.get("version").?.float);
}

test "Parse object with multi-line comment" {
    const input = "{\n" ++
        "  /*\n" ++
        "  multi-line\n" ++
        "   comments\n" ++
        "   */\n" ++
        "  \"lang\": \"zig\", // programming language\n" ++
        "  \"version\" : 0.14\n" ++
        "}";
    const allocator = testing.allocator;

    var parser = JsonParser.init(allocator, input);
    defer parser.deinit();

    var parsed = try parser.parse(allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .object);
    try testing.expectEqualStrings("zig", parsed.object.get("lang").?.string.items);
    try testing.expectEqual(0.14, parsed.object.get("version").?.float);
}
