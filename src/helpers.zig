const std = @import("std");
const types = @import("types.zig");
const bart = @import("bart.zig");

const Entry = types.Entry;
const EntryValue = Entry.EntryValue;

pub fn reader_next_or_null(reader:*std.Io.Reader) error{ReadFailed}!?u8 {
    return reader.takeByte() catch |e| switch (e) {
        error.EndOfStream => null,
        error.ReadFailed => error.ReadFailed
    };
}

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

pub fn looks_like(in:[]u8) std.meta.Tag(EntryValue) {
    if (in.len == 0) return .string;
    _ = for (if (in[0] == '-') in[@min(1, in.len-1)..] else in) |b| {
        if (!std.ascii.isDigit(b)) break null;
    } else
        return .number;

    return
        if (std.mem.eql(u8, "true", in) or std.mem.eql(u8, "false", in)) 
            .bool
        else
            .string;
}

pub fn parse_value(alloc:std.mem.Allocator, in:[]u8) !EntryValue {
    return switch (looks_like(in)) {
        .bool => .{ .bool = std.mem.eql(u8, "true", in) },

        .string => 
            if (looks_like(in) != .number) blk :{
                const unstrung =
                    if (in.len > 1)
                        if (in[0] == '"' and in[in.len-1] == '"') in[1..in.len-1] else in
                    else
                        in;
                break :blk .{ .string = try alloc.dupe(u8, unstrung) };
            } else
                error.InvalidValue,

        .number => .{
            .number = std.fmt.parseInt(i256, in, 10) catch {
                return error.UncaughtNumberError;
            }
        },

        else => unreachable,
    };
}

pub fn mk_category(alloc:std.mem.Allocator) !EntryValue {
    return .{
        .category = try alloc.alloc(*Entry, 0),
    };
}

pub fn validate(alloc:std.mem.Allocator, src:[]u8) !bool {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer _ = arena.deinit();

    var res = bart.parse(arena.allocator(), src) catch |e|
        return
            if (e != error.OutOfMemory)
                false
            else
                e; //OOM

    res.deinit(alloc);
    return true;
}

pub fn contains_any_of(str:[]u8, things:[]u8) bool {
    return for (str) |b| {
        if (std.mem.count(u8, things, &[_]u8{b}) > 0) break true;
    } else
        false;
}
