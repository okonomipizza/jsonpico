const std = @import("std");
const testing = std.testing;

pub const JsonParser = @import("parse.zig").JsonParser;
pub const JsonError = @import("type.zig").JsonError;
pub const JsonValue = @import("type.zig").JsonValue;

fn expectString(object: anytype, key: []const u8, expected: []const u8) !void {
    try testing.expectEqualStrings(expected, object.get(key).?.string.items);
}

test "parse from json file" {
    const allocator = testing.allocator;

    // Read file
    const file = try std.fs.cwd().openFile("test/test.json", .{});
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 1024*1024);
    defer allocator.free(content);

    // Parse json
    var parser = try JsonParser.init(allocator, content);
    defer parser.deinit(allocator);

    var parsed = try parser.parse(allocator);
    defer parsed.deinit(allocator);

    // Verify root object
    try testing.expect(parsed == .object);
    const root = parsed.object;

    // Verify basic fields
    try expectString(root, "restaurant", "Japanese Restaurant");
    try testing.expect(root.get("location").? == .null);
    try testing.expect(root.get("rating").?.float == 4.5);


    // Verify menu structure
    try testing.expect(root.get("menu").? == .array);
    const menu = root.get("menu").?.array;
    try testing.expectEqual(@as(usize, 1), menu.items.len);

    // Verify category
    const category = menu.items[0].object;
    try expectString(category, "category", "Appetizers");

    // Verify items array
    const items = category.get("items").?.array;
    try testing.expectEqual(@as(usize, 2), items.items.len);

    // Verify individual items
    const sashimi = items.items[0].object;
    try expectString(sashimi, "name", "Assorted Sashimi Platter");
    try testing.expectEqual(1500, sashimi.get("price").?.integer);
    try testing.expect(sashimi.get("available").?.bool);

    const chawanmushi = items.items[1].object;
    try expectString(chawanmushi, "name", "Chawanmushi");
    try testing.expectEqual(800, chawanmushi.get("price").?.integer);
    try testing.expect(!chawanmushi.get("available").?.bool);
}
