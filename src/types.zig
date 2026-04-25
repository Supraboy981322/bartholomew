const std = @import("std");

const assert = std.debug.assert;

pub const ParseError = error{
    UncaughtNumberError,
    UnexpectedEqualSign,
    UnexpectedBackslash,
    UnexpectedSemiColon,
    UnexpectedOpenBrace,
    UnexpectedCloseBrace,
    UnexpectedOpenBracket,
    UnexpectedCloseBracket,
    UnexpectedEOF,
} || Entry.AppendError;

pub const Entry = struct {
    name:[]u8,
    value:EntryValue,
    parent_category:*Entry = @constCast(&Entry.skeleton),
    category_depth:usize = 0,
    is_skeleton:bool = false,
    string_type:?u8 = null,

    pub const EntryValue = union(enum) {
        string:[]u8,
        number:i256, //why not?
        bool:bool,
        category:[]*Entry,
        list:[]EntryValue,
    };

    pub const ValueType = std.meta.Tag(EntryValue);


    pub const skeleton:Entry = .{
        .name = "",
        .value = .{ .number = 0 },
        .parent_category = @constCast(&Entry.skeleton),
        .category_depth = 0,
        .is_skeleton = true,
    };

    pub const AppendError = error{
        NoName,
        NotCategory,
    };

    pub fn append(
        self:*Entry,
        alloc:std.mem.Allocator,
        thing:EntryValue,
        name:[]u8
    ) (error{OutOfMemory} || AppendError)!*Entry {
        if (name.len < 1)
            return error.NoName;
        if (self.value != .category)
            return error.NotCategory;

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

        {
            var should_free_name = !self.parent_category.is_skeleton;
            should_free_name = should_free_name or self.category_depth > 0;
            should_free_name = should_free_name or self.value != .category;
            if (should_free_name)
                alloc.free(self.name)
            else if (!std.mem.eql(u8, "root", self.name))
                std.debug.panic(
                    "failed to free non-root category name: |{s}| (depth {d})",
                    .{self.name, self.category_depth}
                );
        }

        switch (self.value) {
            .number, .bool => {},

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
                    .number, .bool => {},
                    else => unreachable, //lists cannot (currently) have anything else
                };
                alloc.free(list);
            }
        }
    }

    pub fn init(alloc:std.mem.Allocator) !Entry {
        return .{
            .name = @constCast("root"),
            .value = .{
                .category = try alloc.alloc(*Entry, 0),
            },
        };
    }

    pub fn get_root(self:*Entry) !*Entry {
        if (self.value != .category)
            return error.NotCategory;
        var cur:*Entry = self;
        return while (!cur.parent_category.is_skeleton) {
            cur = cur.parent_category;
        } else
            cur;
    }

    pub fn getAny(
        self:*Entry,
        name:[]const u8
    ) !*Entry {
        if (self.value != .category)
            return error.NotCategory;
        return for (self.value.category) |entry| {
            if (std.mem.eql(u8, entry.name, name)) break entry;
        } else
            error.FieldNotFound;
    }

    pub fn traverse(
        self:*Entry,
        comptime expecting:ValueType,
        path:[]const u8
    ) !switch (expecting) {
        .category => Entry,
        .string => []u8,
        .number => i256,
        .bool => bool,
        .list => []EntryValue,
    } {
        var itr = std.mem.splitScalar(u8, path, '>');
        var cur:*Entry = self;
        while (itr.next()) |name| {

            if (cur.value != .category)
                return error.NotCategory;

            cur = inner: for (cur.value.category) |entry| {
                if (std.mem.eql(u8, entry.name, name)) {
                    break :inner entry;
                }
            } else
                return error.FieldNotFound;

            if (itr.peek()) |_| if (cur.value != .category)
                return error.NotCategory;
        }

        if (cur.value != expecting)
            return error.WrongType;

        return switch (expecting) {
            .string => cur.value.string,
            .category => cur.*,
            .bool => cur.value.bool,
            .list => cur.value.list,
            .number => cur.value.number,
        };
    }
};

pub const SerializeOpts = struct {
    skip_root:bool = true,
    use_newline:bool = true,
    use_no_quotes:bool = false,
    tab:TabOpts = .{
        .width = 1,
        .char = '\t',
    },

    pub const TabOpts = struct {
        width:u3,
        char:u8,

        pub const none = TabOpts{
            .width = 0,
            .char = 0,
        };
    };

    pub const default:SerializeOpts = .{};

    pub fn compact(self:SerializeOpts) SerializeOpts {
        var new = self;
        new.tab = .none;
        new.use_newline = false;
        return new;
    }

    pub fn include_root(self:SerializeOpts) SerializeOpts {
        var new = self;
        new.skip_root = false;
        return new;
    }

    pub fn set_tab(self:SerializeOpts, char:u8) SerializeOpts {
        var new = self;
        new.tab = .{
            .width = 1,
            .char = char,
        };
        return new;
    }

    pub fn expand_tab(self:SerializeOpts, width:u3) SerializeOpts {
        var new = self;
        new.tab.width = width;
        return new;
    }
};
