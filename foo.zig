const std = @import("std");

const Entry = struct {
    name:[]u8,
    value:EntryValue,
    parent_category:*Entry = @constCast(&Entry.skeleton),
    category_depth:usize = 0,

    pub const EntryValue = union(enum) {
        string:[]u8,
        number:i256, //why not?
        category:[]Entry,
        list:[]EntryValue,
    };

    pub const skeleton:Entry = .{
        .name = "",
        .value = .{ .number = 0 },
        .parent_category = @constCast(&Entry.skeleton),
        .category_depth = 0,
    };

    pub fn append(self:*Entry, alloc:std.mem.Allocator, thing:EntryValue, name:[]u8) !*Entry {
        if (self.value != .category)
            return error.Notcategory;
        var new = try alloc.alloc(Entry, self.value.category.len + 1);
        for (self.value.category, 0..) |entry, i|
            new[i] = entry;
        new[new.len-1] = .{
            .name = name,
            .value = thing
        };
        alloc.free(self.value.category);
        self.value.category = new;
        var new_entry:*Entry = @constCast(&self.value.category[self.value.category.len - 1]);
        new_entry.category_depth = self.category_depth + 1;
        if (thing == .category) {
            new_entry.parent_category = self;
            std.debug.assert(new_entry.parent_category.category_depth == self.category_depth);
        }
        return new_entry;
    }

    pub fn deinit(self:*Entry, alloc:std.mem.Allocator) void {
        for (0..self.category_depth) |_|
            std.debug.print("  ", .{});
        std.debug.print("{s} ", .{self.name});
        alloc.free(self.name);
        switch (self.value) {
            .string => |str| {
                std.debug.print("= {s}\n", .{str});
                alloc.free(str);
            },
            .category => |category| {
                std.debug.print("{{\n", .{});
                for (category) |*entry| @constCast(entry).deinit(alloc);
                for (0..self.category_depth) |_|
                    std.debug.print("  ", .{});
                std.debug.print("}}\n", .{});
            },
            .number => |n| {
                std.debug.print("= {d}\n", .{n});
            },
            .list => |list| {
                std.debug.print("= [\n", .{});
                for (list) |entry| {
                    for (0..self.category_depth+1) |_|
                        std.debug.print("  ", .{});
                    switch (entry) {
                        .string => |str| {
                            std.debug.print("{s}\n", .{str});
                            alloc.free(str);
                        },
                        .number => |n| std.debug.print("{d}\n", .{n}),
                        else => unreachable,
                    }
                }
                alloc.free(list);
                for (0..self.category_depth) |_|
                    std.debug.print("  ", .{});
                std.debug.print("]\n", .{});
            }
        }
    }
};

pub fn main(init:std.process.Init) !void {
    var io = init.io;
    const alloc = init.gpa;
    _ = .{ &io, alloc };

    const src = 
        \\# source
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
    ;
    std.debug.print("{s}", .{src});

    var cur_category:*Entry = @constCast(&Entry{
        .name = try alloc.dupe(u8, "root"),
        .value = .{
            .category = try alloc.alloc(Entry, 0)
        }, 
    });
    defer {
        while (cur_category.category_depth > 0) {
            cur_category = cur_category.parent_category;
        }
        std.debug.print("\n\n=== tokenized ===\n", .{});
        cur_category.deinit(alloc);
    }

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

        blk: {
            if (std.ascii.isWhitespace(b) and cur_list == null)
                continue
            else if (cur_list) |*list| if (mem.items.len > 0) {
                if (b == ']')
                    break :blk;

                const is_dig = for (mem.items) |c| {
                    if (!std.ascii.isDigit(c)) break false;
                } else
                    true;

                const new:Entry.EntryValue = if (is_dig) .{
                    .number = std.fmt.parseInt(i256, mem.items, 10) catch unreachable,
                } else .{
                    .string = try mem.toOwnedSlice(alloc)
                };
                try list.append(alloc, new);
                mem.clearAndFree(alloc);
                continue;
            } else if (std.ascii.isWhitespace(b))
                    continue;
        }

        switch (b) {

            '=' => {
                if (name.len > 0)
                    unreachable; // TODO: error here
                name = try mem.toOwnedSlice(alloc);
            },

            '\\' => if (string != 0) {
                esc = true;
            } else
                unreachable, // TODO: error here

            '"', '\'' => string = b,

            ';' => {
                if (mem.items.len < 1)
                    unreachable; // TODO: error

                defer name = "";

                const is_dig = for (mem.items) |c| {
                    if (!std.ascii.isDigit(c)) break false;
                } else
                    true;

                const new:Entry.EntryValue = if (is_dig) .{
                    .number = std.fmt.parseInt(i256, mem.items, 10) catch unreachable,
                } else .{
                    .string = try mem.toOwnedSlice(alloc)
                };

                _ = try cur_category.append(alloc, new, name);

                mem.clearAndFree(alloc);
            },

            '{' => if (mem.items.len > 0) {
                const new_category:Entry.EntryValue = .{
                    .category = try alloc.alloc(Entry, 0)
                };
                cur_category = try cur_category.append(
                    alloc,
                    new_category,
                    try mem.toOwnedSlice(alloc)
                );
            } else
                unreachable, // TODO: error here

            '}' => {
                if (cur_category.category_depth > 0)
                    cur_category = cur_category.parent_category;
            },
            
            '[' => {
                if (cur_list) |_|
                    unreachable; // TODO: error here
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
                    unreachable; // TODO: error here
            },

            '#' => {
                i.? += 1;
                while (src[i.?] != '\n') : (i.? += 1) {}
                continue;
            },

            else => try mem.append(alloc, b),
        }
    }
}
