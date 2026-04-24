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
        assert(name.len > 0);
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
            assert(new_entry.parent_category.category_depth == self.category_depth);
        }
        return new_entry;
    }

    pub fn deinit(self:*Entry, alloc:std.mem.Allocator) void {
        if (!self.is_skeleton)
            alloc.free(self.name);
        switch (self.value) {
            .number => {},

            .string => |str| alloc.free(str),

            .category => |category| {
                for (category) |*entry|
                    @constCast(entry).deinit(alloc);
            },

            .list => |list| {
                for (list) |entry| switch (entry) {
                    .string => |str| alloc.free(str),
                    .number => {},
                    else => unreachable,
                };
                alloc.free(list);
            }
        }
    }
};
