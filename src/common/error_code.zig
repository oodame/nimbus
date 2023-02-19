const std = @import("std");

pub const ReadError = error {
    WouldBlock,
    NotOpenForRead,
    Connection,
};

/// This is the global error codes
pub const ErrorCode = ReadError;