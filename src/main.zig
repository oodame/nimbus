const std = @import("std");
const nimbus = @import("nimbus");

fn cmp(a: []const u8, b: []const u8) i32 {
    if (std.mem.eql(u8, a, b)) {
        return 0;
    }
    return if (std.mem.lessThan(u8, a, b)) -1 else 1;
}

const Cmp = struct {
    fn compare(a: []const u8, b: []const u8) std.math.Order {
        return std.mem.order(u8, a, b);
    }
};

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    // try nimbus.bufferedPrint();
    var skiplist = try nimbus.SkipList([]const u8, []const u8).init(std.heap.page_allocator, Cmp.compare);
    defer skiplist.deinit();
    try skiplist.put("hello", "world");
    const value = skiplist.get("hello");
    std.debug.print("The value for 'hello' is: {s}\n", .{value.?});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

test "compare" {
    const a = &[_]u8{0};
    const b = "hello";
    try std.testing.expect(cmp(a, b) < 0);
    std.debug.print("Comparison result: {d}\n", .{cmp(a, b)});
}
