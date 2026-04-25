const std = @import("std");
const types = @import("types.zig");

pub fn quote(alloc:std.mem.Allocator, raw:[]u8, string_type:u8) ![]u8 {
    var res = try std.ArrayList(u8).initCapacity(alloc, raw.len);
    defer res.deinit(alloc);
    try res.append(alloc, string_type);
    for (raw) |b| {
        try res.appendSlice(alloc,
            if (b == string_type)
                &[_]u8{ '\\', b }
            else
                &[_]u8{b}
        );
    }
    try res.append(alloc, string_type);
    return res.toOwnedSlice(alloc);
}

pub fn looks_like(in:[]u8) std.meta.Tag(types.Entry.EntryValue) {
    _ = for (in) |b| {
        if (!std.ascii.isDigit(b)) break null;
    } else
        return .number;

    return
        if (std.mem.eql(u8, "true", in) or std.mem.eql(u8, "false", in)) 
            .bool
        else
            .string;
}

pub fn parse_value(alloc:std.mem.Allocator, in:[]u8) !types.Entry.EntryValue {
    return switch (looks_like(in)) {
        .bool => .{ .bool = std.mem.eql(u8, "true", in) },
        .string => .{ .string = try alloc.dupe(u8, in) },
        .number => .{ .number = std.fmt.parseInt(i256, in, 10) catch return error.UncaughtNumberError },
        else => unreachable,
    };
}

pub fn mk_category(alloc:std.mem.Allocator) !EntryValue {
    return .{
        .category = try alloc.alloc(*Entry, 0),
    };
}
