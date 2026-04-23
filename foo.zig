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
        \\}
    ;

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

    var name:[]u8 = "";

    while (
        if (i) |idx| idx < src.len else true
    ) : ({
        i = if (i) |idx| idx + 1 else 0;
        if (i.? >= src.len) break;
        b = src[i.?];
    }) {
        std.debug.print("{c}", .{b});

        if (string != 0 or esc) {
            if (esc)
                try mem.append(alloc, b)
            else if (string == b)
                string = 0
            else
                try mem.append(alloc, b);
            continue;
        }

        if (std.ascii.isWhitespace(b)) continue;
        switch (b) {
            '=' => {
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
                const is_dig = for (mem.items) |c| {
                    if (!std.ascii.isDigit(c)) break false;
                } else
                    true;

                if (is_dig) {
                    _ = try cur_category.append(alloc, .{
                        .number = std.fmt.parseInt(i256, mem.items, 10) catch unreachable,
                    }, name);
                    mem.clearAndFree(alloc);
                    continue;
                }

                _ = try cur_category.append(alloc, .{
                    .string = try mem.toOwnedSlice(alloc),
                }, name);
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


            '#' => {
                i.? += 1;
                while (src[i.?] != '\n') : (i.? += 1) {
                    std.debug.print("{c}", .{src[i.?]});
                }
                std.debug.print("\n", .{});
                continue;
            },

            '}' => {
                if (cur_category.category_depth > 0)
                    cur_category = cur_category.parent_category;
            },

            else => try mem.append(alloc, b),
        }
    }
}
