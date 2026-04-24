const std = @import("std");

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
}
