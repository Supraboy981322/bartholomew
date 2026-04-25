const std = @import("std");
const bart = @import("bart.zig");

const Entry = bart.Entry;

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
        \\  bar = true;
        \\  foo = [
        \\    1
        \\    9875
        \\    false
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

test "bad input" {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();

    var io = std.Io.Threaded.init(alloc, .{});
    defer io.deinit();

    const random = (std.Random.IoSource{ .io = io.io() }).interface();
    comptime var chars:[]u8 = @constCast("{};[]=" ++ std.ascii.letters);
    inline for ('0'..'9'+1) |b| chars = @constCast(chars ++ [_]u8{b});

    for (0..10) |_| {
        var buf:[1024]u8 = undefined;
        for (buf, 0..) |_, i|
            buf[i] = chars[random.uintAtMost(usize, chars.len-1)];
        if (try bart.validate(alloc, &buf)) unreachable; //returned that Bartholomew is valid (bad) (garbage input)
    }
}

test "compact serialization" {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();

    const src = @constCast(
        \\foo {
        \\  bar = "baz";
        \\}
    );

    var res = try bart.parse(alloc, src);
    defer res.deinit(alloc);

    const serialized = try bart.serialize(alloc, &res, @as(bart.SerializeOpts, .default).compact());
    defer alloc.free(serialized);
    try std.testing.expectEqualSlices(u8, "foo{bar=\"baz\";}", serialized);
}

test "quote string" {
    const alloc = std.testing.allocator;
    const src = @constCast(
        \\foo
    );

    const quoted = try bart.quote(alloc, src, '"');
    defer alloc.free(quoted);
    try std.testing.expectEqualSlices(u8, "\"foo\"", quoted);
}
