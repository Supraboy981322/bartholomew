const std = @import("std");
const bart = @import("bart.zig");

test "basic test" {
    const src:[]u8 = @constCast(@embedFile("test.bart"));

    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();

    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();

    var res = bart.parse(alloc, src) catch |e| @panic(@errorName(e));
    defer res.deinit(alloc);
}
