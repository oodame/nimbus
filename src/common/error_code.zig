const std = @import("std");

/// This is the global error codes
const ErrorCode = error {
    // File related
    FileNotExist,
    OutOfMemory,
};