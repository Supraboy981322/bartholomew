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

    const serialized = try bart.serialize(alloc, &res, .{
        .tab = .{
            .char = .space,
            .width = 2,
        }
    });
    defer alloc.free(serialized);
    if (!std.mem.eql(u8, serialized, src)) {
        try std.testing.expectEqualSlices(u8, src, serialized);
    }
}
