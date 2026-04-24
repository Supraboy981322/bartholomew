const std = @import("std");
const bart = @import("bart.zig");

test "basic test" {
    const src:[]u8 = @constCast(@embedFile("test.bart"));

    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();

    var res = try bart.parse(alloc, src);
    defer res.deinit(alloc);

    const serialized = try bart.serialize(alloc, &res);
    defer alloc.free(serialized);
    std.debug.print("{s}\n", .{serialized});
}
