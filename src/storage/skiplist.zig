//! A LevelDB style skip list
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MemoryCmp = struct {
    pub fn compare(a: []const u8, b: []const u8) std.math.Order {
        return std.mem.order(u8, a, b);
    }
};

pub fn SkipList(comptime KeyType: type, comptime ValueType: type) type {
    return struct {
        const Self = @This();
        const CmpFn = fn (a: KeyType, b: KeyType) std.math.Order;
        const AtomicNodePtr = std.atomic.Value(?*Node);

        const max_level = 12;

        allocator: std.heap.ArenaAllocator,
        levels: std.atomic.Value(u32),
        head: *Node,
        cmp: *const CmpFn,
        rng: std.Random.Xoshiro256,

        const Node = struct {
            key: KeyType,
            value: ValueType,
            // we do not use trailing array because of fields reordering issues
            // nexts: [0]AtomicNodePtr,

            pub fn next(self: *const Node, level: u32) ?*Node {
                return self.nextConstPtr()[level].load(.acquire);
            }

            pub fn nextNoBarrier(self: *const Node, level: u32) ?*Node {
                return self.nextConstPtr()[level].load(.unordered);
            }

            pub fn setNext(self: *Node, level: u32, node: ?*Node) void {
                self.nextPtr()[level].store(node, .release);
            }

            pub fn setNextNoBarrier(self: *Node, level: u32, node: ?*Node) void {
                self.nextPtr()[level].store(node, .unordered);
            }

            pub fn nextPtr(self: *Node) [*]AtomicNodePtr {
                return @ptrCast(@alignCast(@as([*]u8, @ptrCast(self)) + nextOffset()));
            }

            pub fn nextConstPtr(self: *const Node) [*]const AtomicNodePtr {
                return @ptrCast(@alignCast(@as([*]const u8, @ptrCast(self)) + nextOffset()));
            }

            inline fn nextOffset() usize {
                return std.mem.alignForward(usize, @sizeOf(Node), @alignOf(AtomicNodePtr));
            }
        };

        const Iterator = struct {
            list: *const Self,
            node: ?*const Node,

            pub fn init(list: *const Self) Iterator {
                return .{
                    .list = list,
                    .node = list.head.next(0),
                };
            }

            pub fn next(self: *Iterator) ?*const Node {
                const current = self.node orelse return null;
                self.node = current.next(0);
                return current;
            }

            pub fn prev(self: *Iterator) ?*const Node {
                self.node = if (self.node) |n| self.list.findLessThan(n.key) else null;
                return self.node;
            }

            // seek to a key that is >= the given key
            pub fn seek(self: *Iterator, key: KeyType) void {
                self.node = self.list.findGreaterOrEqual(key, null);
            }
        };

        // This is inefficient, because we have to seek in each iteration
        const ReverseIterator = struct {
            list: *const Self,
            node: ?*const Node,

            pub fn init(list: *const Self) ReverseIterator {
                var iter = ReverseIterator{
                    .list = list,
                    .node = list.findLast(),
                };
                // handle empty list
                if (iter.node != null and iter.node.? == list.head) {
                    iter.node = null;
                }
                return iter;
            }

            pub fn next(self: *ReverseIterator) ?*const Node {
                const current = self.node orelse return null;
                self.node = self.list.findLessThan(current.key);
                // if we reached head, return null
                if (self.node != null and self.node.? == self.list.head) {
                    self.node = null;
                }
                return current;
            }

            // seek to a key that is <= the given key
            pub fn seek(self: *ReverseIterator, key: KeyType) void {
                self.node = self.list.findLessOrEqual(key);
                // if we reached head, return null
                if (self.node != null and self.node.? == self.list.head) {
                    self.node = null;
                }
            }
        };

        pub fn init(allocator: Allocator, cmp: *const CmpFn) !Self {
            var self = Self{
                .allocator = std.heap.ArenaAllocator.init(allocator),
                .levels = std.atomic.Value(u32).init(1),
                .head = undefined,
                .cmp = cmp,
                .rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())),
            };
            errdefer self.allocator.deinit();
            // we never use head's key to compare input keys, so it's safe to initialize it with zeroes
            const head = try allocNode(self.allocator.allocator(), max_level, std.mem.zeroes(KeyType), std.mem.zeroes(ValueType));
            self.head = head;
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.deinit();
        }

        pub fn put(self: *Self, key: KeyType, value: ValueType) !void {
            var prev: [max_level]*Node = undefined;
            const node = self.findGreaterOrEqual(key, &prev);
            // because duplicate keys are assigned with different sequence numbers
            std.debug.assert(node == null or self.cmp(key, node.?.key) != .eq);

            const new_level = self.randomLevel();
            if (new_level > self.maxLevel()) {
                const old_level = self.maxLevel();
                for (old_level..new_level) |level| {
                    prev[level] = self.head;
                }
                self.levels.store(new_level, .unordered);
            }

            // insert new_node after prev nodes
            const new_node = try allocNode(self.allocator.allocator(), new_level, key, value);
            for (0..new_level) |level| {
                new_node.setNextNoBarrier(@intCast(level), prev[level].nextNoBarrier(@intCast(level)));
                prev[level].setNext(@intCast(level), new_node);
            }
        }

        pub fn get(self: *Self, key: KeyType) ?ValueType {
            const node = self.findGreaterOrEqual(key, null);
            if (node != null and self.cmp(node.?.key, key) == .eq) {
                return node.?.value;
            } else {
                return null;
            }
        }

        pub fn iterator(self: *Self) Iterator {
            return Iterator.init(self);
        }

        pub fn reverseIterator(self: *Self) ReverseIterator {
            return ReverseIterator.init(self);
        }

        fn findGreaterOrEqual(self: *const Self, key: KeyType, prev: ?[]*Node) ?*Node {
            var node = self.head;
            var level = self.maxLevel() - 1;
            while (true) {
                const next = node.next(level);
                if (self.isKeyAfterNode(key, next)) {
                    node = next orelse return null; // move forward in the level
                } else {
                    if (prev != null) {
                        prev.?[level] = node;
                    }
                    if (level == 0) {
                        return next;
                    }
                    level -= 1;
                }
            }
        }

        fn findLessThan(self: *const Self, key: KeyType) ?*Node {
            var node = self.head;
            var level = self.maxLevel() - 1;
            while (true) {
                std.debug.assert(node == self.head or self.cmp(node.key, key) == .lt);
                const next = node.next(level);
                if (next == null or self.cmp(next.?.key, key) != .lt) {
                    if (level == 0) {
                        return node;
                    } else {
                        // Descend to the next level
                        level -= 1;
                    }
                } else {
                    node = next.?;
                }
            }
        }

        fn findLessOrEqual(self: *const Self, key: KeyType) ?*Node {
            var node = self.head;
            var level = self.maxLevel() - 1;
            while (true) {
                std.debug.assert(node == self.head or self.cmp(node.key, key) != .gt);
                const next = node.next(level);
                if (next == null or self.cmp(next.?.key, key) == .gt) {
                    if (level == 0) {
                        return node;
                    } else {
                        // Descend to the next level
                        level -= 1;
                    }
                } else {
                    node = next.?;
                }
            }
        }

        fn findLast(self: *const Self) ?*Node {
            var node = self.head;
            var level = self.maxLevel() - 1;
            while (true) {
                const next = node.next(level);
                // end of this level
                if (next == null) {
                    if (level == 0) {
                        return node;
                    } else {
                        level -= 1;
                    }
                } else {
                    node = next.?;
                }
            }
        }

        // null means end of a level
        fn isKeyAfterNode(self: *const Self, key: KeyType, node: ?*Node) bool {
            return node != null and self.cmp(node.?.key, key) == .lt;
        }

        fn maxLevel(self: *const Self) u32 {
            return self.levels.load(.unordered);
        }

        fn randomLevel(self: *Self) u32 {
            var level: u32 = 1;
            while (self.rng.random().int(u32) % 4 == 0 and level < max_level) : (level += 1) {}
            std.debug.assert(level <= max_level);
            return level;
        }

        fn allocNode(allocator: Allocator, level: u32, key: KeyType, value: ValueType) !*Node {
            std.debug.assert(level <= max_level);
            const off = std.mem.alignForward(usize, @sizeOf(Node), @alignOf(AtomicNodePtr));
            const alignment = comptime std.mem.Alignment.max(std.mem.Alignment.of(Node), std.mem.Alignment.of(AtomicNodePtr));
            const mem = try allocator.alignedAlloc(u8, alignment, off + @sizeOf(AtomicNodePtr) * level);
            const node = @as(*Node, @ptrCast(@alignCast(mem.ptr)));
            node.key = key;
            node.value = value;
            const nexts_ptr = node.nextPtr();
            for (0..level) |i| {
                nexts_ptr[i] = AtomicNodePtr.init(null);
            }
            return node;
        }
    };
}

const testing = std.testing;

test "empty" {
    const allocator = testing.allocator;
    var skiplist = try SkipList([]const u8, []const u8).init(allocator, &MemoryCmp.compare);
    defer skiplist.deinit();
    const value = skiplist.get("nonexistent");
    try std.testing.expect(value == null);
}

test "SkipList: basic put and get" {
    const allocator = testing.allocator;
    var list = try SkipList([]const u8, []const u8).init(allocator, &MemoryCmp.compare);
    defer list.deinit();

    try list.put("apple", "red");
    try list.put("banana", "yellow");
    try list.put("grape", "purple");

    try testing.expectEqualStrings("red", list.get("apple").?);
    try testing.expectEqualStrings("yellow", list.get("banana").?);
    try testing.expectEqualStrings("purple", list.get("grape").?);
    try testing.expect(list.get("orange") == null);
}

test "SkipList: iterator forward" {
    const allocator = testing.allocator;
    var list = try SkipList([]const u8, i32).init(allocator, &MemoryCmp.compare);
    defer list.deinit();

    try list.put("a", 1);
    try list.put("c", 3);
    try list.put("b", 2);

    var it = list.iterator();

    const n1 = it.next().?;
    try testing.expectEqualStrings("a", n1.key);

    const n2 = it.next().?;
    try testing.expectEqualStrings("b", n2.key);

    const n3 = it.next().?;
    try testing.expectEqualStrings("c", n3.key);

    try testing.expect(it.next() == null);
}

test "SkipList: forward seek" {
    const allocator = testing.allocator;
    var list = try SkipList([]const u8, i32).init(allocator, &MemoryCmp.compare);
    defer list.deinit();

    try list.put("1", 10);
    try list.put("3", 30);
    try list.put("5", 50);

    var it = list.iterator();
    it.seek("2");
    try testing.expectEqualStrings("3", it.node.?.key);

    it.seek("4");
    try testing.expectEqualStrings("5", it.node.?.key);

    it.seek("5");
    try testing.expectEqualStrings("5", it.node.?.key);
}

test "SkipList: seek outside boundaries" {
    const allocator = testing.allocator;
    var list = try SkipList(i32, i32).init(allocator, &struct {
        fn cmp(a: i32, b: i32) std.math.Order {
            return std.math.order(a, b);
        }
    }.cmp);
    defer list.deinit();

    try list.put(10, 100);
    try list.put(20, 200);

    var it = list.iterator();
    it.seek(30);
    try testing.expect(it.node == null);
    try testing.expect(it.next() == null);

    it.seek(5);
    try testing.expectEqual(@as(i32, 10), it.node.?.key);
    try testing.expectEqual(@as(i32, 10), it.next().?.key);

    var rit = list.reverseIterator();
    rit.seek(5);
    try testing.expect(rit.node == null);
    try testing.expect(rit.next() == null);

    rit.seek(25);
    try testing.expectEqual(@as(i32, 20), rit.node.?.key);
}

test "SkipList: iterator backward" {
    const allocator = testing.allocator;
    var list = try SkipList([]const u8, i32).init(allocator, &MemoryCmp.compare);
    defer list.deinit();

    try list.put("a", 1);
    try list.put("c", 3);
    try list.put("b", 2);

    var it = list.reverseIterator();

    const n1 = it.next().?;
    try testing.expectEqualStrings("c", n1.key);

    const n2 = it.next().?;
    try testing.expectEqualStrings("b", n2.key);

    const n3 = it.next().?;
    try testing.expectEqualStrings("a", n3.key);

    try testing.expect(it.next() == null);
}

test "SkipList: backward seek" {
    const allocator = testing.allocator;
    var list = try SkipList([]const u8, i32).init(allocator, &MemoryCmp.compare);
    defer list.deinit();

    try list.put("1", 10);
    try list.put("3", 30);
    try list.put("5", 50);

    var it = list.reverseIterator();
    it.seek("2");
    try testing.expectEqualStrings("1", it.node.?.key);

    it.seek("4");
    try testing.expectEqualStrings("3", it.node.?.key);

    it.seek("5");
    try testing.expectEqualStrings("5", it.node.?.key);
}

test "SkipList: i32 keys with custom comparator" {
    const i32_helper = struct {
        fn cmp(a: i32, b: i32) std.math.Order {
            return std.math.order(a, b);
        }
    };

    const allocator = testing.allocator;
    var list = try SkipList(i32, []const u8).init(allocator, &i32_helper.cmp);
    defer list.deinit();

    try list.put(100, "one hundred");
    try list.put(50, "fifty");
    try list.put(200, "two hundred");

    try testing.expectEqualStrings("fifty", list.get(50).?);
    try testing.expectEqualStrings("two hundred", list.get(200).?);

    var it = list.iterator();
    try testing.expectEqual(@as(i32, 50), it.node.?.key);
    _ = it.next();
    try testing.expectEqual(@as(i32, 100), it.node.?.key);
}

test "SkipList: empty list behavior" {
    const allocator = testing.allocator;
    var list = try SkipList([]const u8, i32).init(allocator, &MemoryCmp.compare);
    defer list.deinit();

    const it1 = list.iterator();
    try testing.expect(it1.node == null);

    const it2 = list.reverseIterator();
    try testing.expect(it2.node == null);

    try testing.expect(list.get("any") == null);
}

test "SkipList: large number of forward inserts" {
    const allocator = testing.allocator;
    const IntList = SkipList(u32, u32);
    const helper = struct {
        fn cmp(a: u32, b: u32) std.math.Order {
            return std.math.order(a, b);
        }
    };

    var list = try IntList.init(allocator, &helper.cmp);
    defer list.deinit();

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        try list.put(i * 2, i);
    }

    try testing.expectEqual(@as(u32, 50), list.get(100).?);
    try testing.expect(list.get(101) == null);

    var it = list.iterator();
    var count: u32 = 0;
    var last_key: u32 = 0;
    while (it.next()) |node| {
        if (count > 0) {
            try testing.expect(node.key > last_key);
        }
        last_key = node.key;
        count += 1;
    }
    try testing.expectEqual(@as(u32, 1000), count);
}

test "SkipList: large number of backward inserts" {
    const allocator = testing.allocator;
    const IntList = SkipList(u32, u32);
    const helper = struct {
        fn cmp(a: u32, b: u32) std.math.Order {
            return std.math.order(a, b);
        }
    };

    var list = try IntList.init(allocator, &helper.cmp);
    defer list.deinit();

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        try list.put(i * 2, i);
    }

    try testing.expectEqual(@as(u32, 50), list.get(100).?);
    try testing.expect(list.get(101) == null);

    var it = list.reverseIterator();
    var count: u32 = 0;
    var last_key: u32 = 0;
    while (it.next()) |node| {
        if (count > 0) {
            try testing.expect(node.key < last_key);
        }
        last_key = node.key;
        count += 1;
    }
    try testing.expectEqual(@as(u32, 1000), count);
}

test "SkipList: empty string and special keys" {
    const allocator = testing.allocator;
    var list = try SkipList([]const u8, i32).init(allocator, &MemoryCmp.compare);
    defer list.deinit();

    // 测试空字符串作为 Key
    try list.put("", 0);
    try list.put("\x00", 1);
    try list.put("\xff", 255);

    try testing.expectEqual(@as(i32, 0), list.get("").?);
    try testing.expectEqual(@as(i32, 1), list.get("\x00").?);
    try testing.expectEqual(@as(i32, 255), list.get("\xff").?);

    var it = list.iterator();
    try testing.expectEqualStrings("", it.next().?.key);
    try testing.expectEqualStrings("\x00", it.next().?.key);
}

test "SkipList: struct as key" {
    const Point = struct {
        x: i32,
        y: i32,

        fn compare(a: @This(), b: @This()) std.math.Order {
            if (a.x != b.x) return std.math.order(a.x, b.x);
            return std.math.order(a.y, b.y);
        }
    };

    const allocator = testing.allocator;
    var list = try SkipList(Point, bool).init(allocator, &Point.compare);
    defer list.deinit();

    try list.put(.{ .x = 1, .y = -2 }, true);
    try list.put(.{ .x = -1, .y = 1 }, false);
    try list.put(.{ .x = 2, .y = 0 }, true);

    // 验证排序 (-1,1) -> (1,-2) -> (2,0)
    var it = list.iterator();
    const p1 = it.next().?.key;
    try testing.expect(p1.x == -1 and p1.y == 1);
    const p2 = it.next().?.key;
    try testing.expect(p2.x == 1 and p2.y == -2);
    const p3 = it.next().?.key;
    try testing.expect(p3.x == 2 and p3.y == 0);
}

test "SkipList: exhaustive interleaved seek and next" {
    const allocator = testing.allocator;
    var list = try SkipList(i32, i32).init(allocator, &struct {
        fn cmp(a: i32, b: i32) std.math.Order {
            return std.math.order(a, b);
        }
    }.cmp);
    defer list.deinit();

    var i: i32 = 0;
    while (i < 100) : (i += 10) try list.put(i, i * 10);

    var it = list.iterator();
    it.seek(15);
    try testing.expectEqual(@as(i32, 20), it.node.?.key);
    _ = it.next();
    try testing.expectEqual(@as(i32, 30), it.node.?.key);

    it.seek(5);
    try testing.expectEqual(@as(i32, 10), it.node.?.key);
}

test "SkipList: reverse iterator with single element" {
    const allocator = testing.allocator;
    var list = try SkipList(i32, i32).init(allocator, &struct {
        fn cmp(a: i32, b: i32) std.math.Order {
            return std.math.order(a, b);
        }
    }.cmp);
    defer list.deinit();

    try list.put(42, 42);

    var rit = list.reverseIterator();
    try testing.expectEqual(@as(i32, 42), rit.next().?.key);
    try testing.expect(rit.next() == null);

    rit.seek(42);
    try testing.expectEqual(@as(i32, 42), rit.node.?.key);
    rit.seek(41);
    try testing.expect(rit.node == null);
}
