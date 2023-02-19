const std = @import("std");
const os = std.os;

const ReadError = @import("../error_code.zig").ReadError;
const Slice = @import("../types/types.zig").Slice;

pub const FileReader = struct {
    file_name: Slice,
    fd: os.fd_t, 

    const Self = @This();

    pub fn read(self: Self, buf: []u8, len: u32, offset: u64) !usize {
        return os.pread(self.fd, buf, len, offset);
    }
};