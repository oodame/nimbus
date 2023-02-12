const std = @import("std");
const builtin = @import("builtin");

pub const platform = builtin.target.os.tag;

const assert = std.debug.assert;

test "darwin" {
    comptime {
        assert(platform == .macos);
    }
}