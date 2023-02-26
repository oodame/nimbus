const std = @import("std");
const os = std.os;
const log = std.log.scoped(.fs);

/// This struct type describes the file io capabilities. 
pub const FileIO = struct {


    /// This union holds the operations for file io. 
    pub const Operation = union(enum) {
        read: struct {
            fd: os.fd_t,
            buf: [*]u8,
            len: u32,
            offset: u64,
        },
        write: struct {
            fd: os.fd_t,
            buf: [*]u8,
            len: u32,
            offset: u64,
        },
        close: struct {
            fd: os.fd_t,        
        },
        timeout: struct {
            expires: u64,
        }
    };

    
};
