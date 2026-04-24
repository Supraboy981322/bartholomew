const std = @import("std");
const hlp = @import("helpers.zig");
const types = @import("types.zig");

const Entry = types.Entry;

pub fn parse(alloc:std.mem.Allocator, src:[]u8) !Entry {

    var cur_category:*Entry = @constCast(&Entry{
        .name = @constCast("root"),
        .value = .{
            .category = try alloc.alloc(*Entry, 0)
        }, 
    });

    var b:u8,
        var string:u8,
        var i:?usize,
        var esc:bool
            = .{ 0, 0, null, false };

    var mem = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer _ = mem.deinit(alloc);

    var cur_list:?std.ArrayList(Entry.EntryValue) = null;
    defer if (cur_list) |*list|
        list.deinit(alloc);

    var name:[]u8 = "";

    while (
        if (i) |idx| idx < src.len else true
    ) : ({
        i = if (i) |idx| idx + 1 else 0;
        if (i.? >= src.len) break;
        b = src[i.?];
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

                const is_dig = for (mem.items) |c| {
                    if (!std.ascii.isDigit(c)) break false;
                } else
                    true;

                const new:Entry.EntryValue = if (is_dig) .{
                    .number = std.fmt.parseInt(i256, mem.items, 10) catch return error.UncaughtNumberError,
                } else .{
                    .string = try mem.toOwnedSlice(alloc)
                };

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

                defer name = "";

                const is_dig = for (mem.items) |c| {
                    if (!std.ascii.isDigit(c)) break false;
                } else
                    true;

                const new:Entry.EntryValue = if (is_dig) .{
                    .number = std.fmt.parseInt(i256, mem.items, 10) catch return error.UncaughtNumberError,
                } else .{
                    .string = try mem.toOwnedSlice(alloc)
                };

                _ = try cur_category.append(alloc, new, name);

                mem.clearAndFree(alloc);
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
                i.? += 1;
                while (src[i.?] != '\n') : (i.? += 1) {}
                continue;
            },

            else => try mem.append(alloc, b),
        }
    }

    while (cur_category.category_depth > 0)
        cur_category = cur_category.parent_category;
    return cur_category;
}
