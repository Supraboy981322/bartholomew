const std = @import("std");
const hlp = @import("helpers.zig");
const types = @import("types.zig");

pub const Entry = types.Entry;
pub const SerializeOpts = types.SerializeOpts;
pub const AppendError = types.Entry.AppendError;
pub const ParseError = types.ParseError;

pub const mk_category = hlp.mk_category;

pub fn parse(
    alloc:std.mem.Allocator,
    src:[]u8
) (error{OutOfMemory} || ParseError)!Entry {

    var cur_category:*Entry = @constCast(&try Entry.init(alloc));
    errdefer {
        @constCast(cur_category.get_root() catch unreachable).*.deinit(alloc);
    }

    var b:u8 = if (src.len > 0) src[0] else 0;
    var string:u8,
        var i:usize,
        var esc:bool
            = .{ 0, 0, false };

    var mem = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer _ = mem.deinit(alloc);

    var cur_list:?std.ArrayList(Entry.EntryValue) = null;
    defer if (cur_list) |*list|
        list.deinit(alloc);

    var name:[]u8 = "";

    while (
        i < src.len
    ) : ({
        i += 1;
        if (i >= src.len) break;
        b = src[i];
    }) {

        if (string != 0 or esc) {
            // TODO: debug (esc and string == b)
            if (esc) {
                try mem.append(alloc, b);
                esc = false;
            } else if (string == b)
                string = 0
            else
                try mem.append(alloc, b);
            continue;
        }

        if (std.ascii.isWhitespace(b)) {
            if (cur_list) |*list| if (mem.items.len > 0) {
                defer mem.clearAndFree(alloc);
                const new = try hlp.parse_value(alloc, mem.items);
                try list.append(alloc, new);
            };
            continue;
        }

        switch (b) {

            '=' => {
                if (name.len > 0)
                    return error.UnexpectedEqualSign;
                name = try mem.toOwnedSlice(alloc);
            },

            '\\' => if (string != 0) {
                esc = true;
            } else
                return error.UnexpectedBackslash,

            // TODO: maybe a little refactor for single quote
            '"' => string = b,

            ';' => {
                if (mem.items.len < 1)
                    return error.UnexpectedSemiColon;
                defer {
                    name = "";
                    mem.clearAndFree(alloc);
                }
                const new = try hlp.parse_value(alloc, mem.items);
                _ = try cur_category.append(alloc, new, name);
            },

            '{' => if (mem.items.len > 0) {
                const new_category:Entry.EntryValue = .{
                    .category = try alloc.alloc(*Entry, 0)
                };
                cur_category = try cur_category.append(
                    alloc,
                    new_category,
                    try mem.toOwnedSlice(alloc)
                );
            } else
                return error.UnexpectedOpenBrace,

            '}' => {
                if (cur_category.category_depth > 0)
                    cur_category = cur_category.parent_category;
            },
            
            '[' => {
                if (cur_list) |_|
                    return error.UnexpectedOpenBracket;
                cur_list = try std.ArrayList(Entry.EntryValue).initCapacity(alloc, 0);
            },

            ']' => {
                if (cur_list) |*list| {
                    _ = try cur_category.append(alloc, .{
                        .list = try list.toOwnedSlice(alloc),
                    }, name);
                    list.deinit(alloc);
                    cur_list = null;
                } else
                    return error.UnexpectedCloseBracket;
            },

            // TODO: move this out of switch statement
            '#' => {
                i += 1;
                while (src[i] != '\n') : (i += 1) {}
                continue;
            },

            else => try mem.append(alloc, b),
        }
    }

    if (mem.items.len > 0)
        return error.UnexpectedEOF;

    while (cur_category.category_depth > 0)
        cur_category = cur_category.parent_category;
    return cur_category.*;
}

pub fn serialize(alloc:std.mem.Allocator, in:*Entry, opts:types.SerializeOpts) ![]u8 {

    if (in.value != .category)
        return error.NotCategory;

    if (in.is_skeleton)
        return error.IsSkeleton;

    var res = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer res.deinit(alloc);

    const tab_offset:usize = if (!opts.skip_root) b: {
        try res.print(alloc, "{s} {{\n", .{in.name});
        break :b 1;
    } else
        0;

    for (in.value.category) |entry| {
        const entry_offset = if (!opts.skip_root)
            tab_offset + entry.category_depth
        else
            entry.category_depth;

        for (0..(entry_offset-1) * opts.tab.width) |_|
            try res.append(alloc, opts.tab.char);

        try res.print(alloc, "{s}{s}", .{entry.name, if (opts.tab.width > 0) " "  else ""});

        switch (entry.value) {
            .number => |n| try res.print(alloc, "={s}{d};", .{if (opts.tab.width > 0) " " else "", n}),
            .string => |str| {
                const slice = try hlp.quote(alloc, str, '"');
                defer alloc.free(slice);
                try res.print(alloc, "={s}{s};", .{if (opts.tab.width > 0) " " else "", slice});
            },

            .bool => |v| try res.print(alloc, "={s}{};", .{if (opts.tab.width > 0) " "  else "", v}),

            .list => |list| {
                try res.print(alloc, "={s}[\n", .{if (opts.tab.width > 0) " " else ""});
                for (list) |item| {
                    for (0..(entry_offset) * opts.tab.width) |_|
                        try res.append(alloc, opts.tab.char);
                    switch (item) {
                        .number => |n| try res.print(alloc, "{d}", .{n}),
                        .string => |str| {
                            const slice = try hlp.quote(alloc, str, '"');
                            defer alloc.free(slice);
                            try res.appendSlice(alloc, slice);
                        },
                        .bool => |v| try res.print(alloc, "{}", .{v}),
                        else => unreachable,
                    }
                    if (opts.use_newline)
                        try res.append(alloc, '\n')
                    else
                        try res.append(alloc, ' ');
                }
                for (0..(entry_offset-1) * opts.tab.width) |_|
                    try res.append(alloc, opts.tab.char);
                try res.append(alloc, ']');
            },
            .category => {
                const slice = try serialize(alloc, entry, opts);
                defer alloc.free(slice);
                try res.print(alloc, "{{{s}{s}{s}", .{
                    if (opts.use_newline) "\n" else "",
                    slice,
                    if (opts.use_newline) "\n" else ""
                });
                for (0..(entry_offset-1) * opts.tab.width) |_|
                    try res.append(alloc, opts.tab.char);
                try res.append(alloc, '}');
            },
        }
        if (opts.use_newline)
            try res.append(alloc, '\n');
    }

    if (!opts.skip_root)
        try res.append(alloc, '}')
    else if (opts.use_newline)
        _ = res.pop(); //remove trailing newline

    return res.toOwnedSlice(alloc);
}

pub fn validate(alloc:std.mem.Allocator, src:[]u8) !bool {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer _ = arena.deinit();

    var res = parse(arena.allocator(), src) catch |e|
        return
            if (e != error.OutOfMemory)
                false
            else
                e; //OOM

    res.deinit(alloc);
    return true;
}
