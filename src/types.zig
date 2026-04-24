const std = @import("std");

const assert = std.debug.assert;

pub const Entry = struct {
    name:[]u8,
    value:EntryValue,
    parent_category:*Entry = @constCast(&Entry.skeleton),
    category_depth:usize = 0,
    is_skeleton:bool = false,

    pub const EntryValue = union(enum) {
        string:[]u8,
        number:i256, //why not?
        category:[]*Entry,
        list:[]EntryValue,
    };

    pub const skeleton:Entry = .{
        .name = "",
        .value = .{ .number = 0 },
        .parent_category = @constCast(&Entry.skeleton),
        .category_depth = 0,
        .is_skeleton = true,
    };

    pub fn append(self:*Entry, alloc:std.mem.Allocator, thing:EntryValue, name:[]u8) !*Entry {
        if (name.len < 1)
            return error.NoName;
        if (self.value != .category)
            return error.Notcategory;

        var entry = try alloc.create(Entry);//, self.value.category.len + 1);
        entry.* = .{
            .name = name,
            .value = thing,
            .category_depth = self.category_depth + 1,
        };

        var new = try alloc.alloc(*Entry, self.value.category.len + 1);

        for (self.value.category, 0..) |old, i|
            new[i] = old;
        new[new.len-1] = entry;

        alloc.free(self.value.category);
        self.value.category = new;

        if (thing == .category) {
            entry.parent_category = self;
            assert(entry.parent_category.category_depth == self.category_depth);
        }

        return entry;
    }

    pub fn deinit(self:*Entry, alloc:std.mem.Allocator) void {
        if (self.is_skeleton) return;
        if (self.value != .category)
            alloc.free(self.name);
        switch (self.value) {
            .number => {},

            .string => |str| alloc.free(str),

            .category => |category| {
                for (category) |entry| {
                    @constCast(entry).deinit(alloc);
                    alloc.destroy(entry);
                }
                alloc.free(category);
            },

            .list => |list| {
                for (list) |entry| switch (entry) {
                    .string => |str| alloc.free(str),
                    .number => {},
                    else => unreachable, //lists cannot (currently) have anything else
                };
                alloc.free(list);
            }
        }
        if (self.value == .category)
            alloc.free(self.name);
    }
};
