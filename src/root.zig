const std = @import("std");
const testing = std.testing;

pub const JsonParser = @import("parse.zig").JsonParser;
pub const JsonValue = @import("type.zig").JsonValue;
pub const ValueRange = @import("parse.zig").ValueRange;
pub const JsonError = @import("type.zig").JsonError;
pub const PositionMap = @import("parse.zig").PositionMap;
pub const CommentRanges = @import("parse.zig").CommentRanges;

fn expectString(object: anytype, key: []const u8, expected: []const u8) !void {
    try testing.expectEqualStrings(expected, object.get(key).?.string.value.items);
}

test "parse from json file" {
    const allocator = testing.allocator;

    // Read file
    const file = try std.fs.cwd().openFile("test/test.json", .{});
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Parse json
    var parser = try JsonParser.init(allocator, content);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    // Verify root object
    try testing.expect(parsed == .object);
    const root = parsed.object.value;

    // Verify basic fields
    try expectString(root, "restaurant", "Japanese Restaurant");
    try testing.expect(root.get("location").? == .null);
    try testing.expect(root.get("rating").?.float.value == 4.5);

    // Verify menu structure
    try testing.expect(root.get("menu").? == .array);
    const menu = root.get("menu").?.array;
    try testing.expectEqual(@as(usize, 1), menu.value.items.len);

    // Verify category
    const category = menu.value.items[0].object.value;
    try expectString(category, "category", "Appetizers");

    // Verify items array
    const items = category.get("items").?.array.value;
    try testing.expectEqual(@as(usize, 2), items.items.len);

    // Verify individual items
    const sashimi = items.items[0].object.value;
    try expectString(sashimi, "name", "Assorted Sashimi Platter");
    try testing.expectEqual(1500, sashimi.get("price").?.integer.value);
    try testing.expect(sashimi.get("available").?.bool.value);

    const chawanmushi = items.items[1].object.value;
    try expectString(chawanmushi, "name", "Chawanmushi");
    try testing.expectEqual(800, chawanmushi.get("price").?.integer.value);
    try testing.expect(!chawanmushi.get("available").?.bool.value);
}
