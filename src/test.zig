const std = @import("std");
const bart = @import("bart.zig");

const assert = std.debug.assert;

test "parse test" {
    const src:[]u8 = @constCast(@embedFile("test.bart"));

    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();

    var res = try bart.parse(alloc, src);
    defer res.deinit(alloc);
}

test "serialize test" {
    const src = @constCast(
        \\server {
        \\  port = 8945;
        \\  name = "foo";
        \\  description = "foo bar baz";
        \\  foo = [
        \\    1
        \\    9875
        \\    "foo bar baz"
        \\  ]
        \\}
    );

    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();

    var res = try bart.parse(alloc, src);
    defer res.deinit(alloc);

    const opts = @as(bart.SerializeOpts, .default).set_tab(' ').expand_tab(2);
    const serialized = try bart.serialize(alloc, &res, opts);
    defer alloc.free(serialized);
    try std.testing.expectEqualSlices(u8, src, serialized);
}

test "empty input" {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();

    var res = try bart.parse(alloc, @constCast(""));
    defer res.deinit(alloc);

    for ([_]bool{
        std.mem.eql(u8, res.name, "root"),
        res.value.category.len == 0,
    }) |check|
        assert(check);

    const serialized = try bart.serialize(alloc, &res, .default);
    defer alloc.free(serialized);
    try std.testing.expectEqualSlices(u8, "", serialized);
}
