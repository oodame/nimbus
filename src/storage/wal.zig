//! Write-Ahead Log (WAL) for crash recovery
//!
//! The WAL provides durability guarantees by recording all write operations
//! before they're applied to MemGraph. On crash recovery, the WAL is replayed
//! to reconstruct the in-memory state.
//!
//! Log Format:
//! - Each record: [header][payload][checksum]
//! - Header: [record_type:u8][payload_len:u32][lsn:u64][timestamp:u64]
//! - Checksum: CRC32 of header + payload

const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;

// Magic number for WAL files
const WAL_MAGIC: [4]u8 = "WAL\x00".*;
const WAL_VERSION: u32 = 1;
const WAL_MAX_FILE_SIZE: usize = 16 * 1024 * 1024; // 16MB per WAL file

/// Types of records in the WAL
const RecordType = enum(u8) {
    /// Invalid record (placeholder)
    invalid = 0,
    /// Full record (complete operation)
    full = 1,
    /// First fragment of a multi-record operation
    first = 2,
    /// Middle fragment of a multi-record operation
    middle = 3,
    /// Last fragment of a multi-record operation
    last = 4,
    /// Checkpoint record
    checkpoint = 5,
};

/// Types of WAL log operations (stored in payload for recovery)
const LogOpType = enum(u8) {
    put_vertex = 1,
    delete_vertex = 2,
    put_edge = 3,
    delete_edge = 4,
};

/// WAL record header
const RecordHeader = packed struct {
    /// Record type
    record_type: RecordType,
    /// Payload length (max 16MB per record)
    payload_len: u32,
    /// Log sequence number
    lsn: u64,
    /// Timestamp (microseconds since epoch)
    timestamp: u64,

    fn init(record_type: RecordType, payload_len: u32, lsn: u64) RecordHeader {
        return .{
            .record_type = record_type,
            .payload_len = payload_len,
            .lsn = lsn,
            .timestamp = @intCast(std.time.microTimestamp()),
        };
    }
};

/// WAL file header
const WalFileHeader = packed struct {
    /// Magic number
    magic: [4]u8,
    /// Version
    version: u32,
    /// Reserved for future use
    reserved: [8]u8,

    fn init() WalFileHeader {
        return .{
            .magic = WAL_MAGIC,
            .version = WAL_VERSION,
            .reserved = [_]u8{0} ** 8,
        };
    }

    fn verify(self: *const WalFileHeader) bool {
        return std.mem.eql(u8, &self.magic, &WAL_MAGIC) and (self.version == WAL_VERSION);
    }
};

/// WAL record for in-memory representation
const WalRecord = struct {
    allocator: Allocator,
    /// Record type
    record_type: RecordType,
    /// Log sequence number
    lsn: u64,
    /// Timestamp
    timestamp: u64,
    /// Payload data (owned)
    payload: []u8,
    /// CRC32 checksum
    checksum: u32,

    fn init(allocator: Allocator, record_type: RecordType, lsn: u64, payload: []u8) !WalRecord {
        const payload_copy = try allocator.dupe(u8, payload);
        errdefer allocator.free(payload_copy);

        const header = RecordHeader.init(record_type, @intCast(payload.len), lsn);
        const checksum = computeChecksum(&header, payload);
        return .{
            .allocator = allocator,
            .record_type = record_type,
            .lsn = lsn,
            .timestamp = header.timestamp,
            .payload = payload_copy,
            .checksum = checksum,
        };
    }

    fn deinit(self: *WalRecord) void {
        self.allocator.free(self.payload);
    }

    fn computeChecksum(header: *const RecordHeader, payload: []u8) u32 {
        var hasher = std.hash.Crc32.init();
        var header_bytes: [@sizeOf(RecordHeader)]u8 = undefined;
        header_bytes[0] = @intFromEnum(header.record_type);
        std.mem.writeInt(u32, header_bytes[1..5], header.payload_len, .little);
        std.mem.writeInt(u64, header_bytes[5..13], header.lsn, .little);
        std.mem.writeInt(u64, header_bytes[13..21], header.timestamp, .little);
        hasher.update(&header_bytes);
        hasher.update(payload);
        return hasher.final();
    }

    fn verify(self: *const WalRecord) bool {
        const header = RecordHeader{
            .record_type = self.record_type,
            .payload_len = @intCast(self.payload.len),
            .lsn = self.lsn,
            .timestamp = self.timestamp,
        };
        const expected = computeChecksum(&header, self.payload);
        return expected == self.checksum;
    }

    /// encode the record into a byte buffer
    fn encode(self: *const WalRecord, buf: []u8) !usize {
        const header_size = @sizeOf(RecordHeader);
        const total_size = header_size + self.payload.len + @sizeOf(u32);

        if (buf.len < total_size) {
            return error.BufferTooSmall;
        }

        // Write header fields manually to match checksum computation
        // Use stored timestamp, not a new one from init()

        // Write header
        buf[0] = @intFromEnum(self.record_type);
        std.mem.writeInt(u32, buf[1..5], @intCast(u32, self.payload.len), .little);
        std.mem.writeInt(u64, buf[5..13], self.lsn, .little);
        std.mem.writeInt(u64, buf[13..21], self.timestamp, .little);

        // Write payload
        @memmove(buf[header_size .. header_size + self.payload.len], self.payload);

        // Write checksum
        std.mem.writeInt(u32, buf[header_size + self.payload.len .. total_size], self.checksum, .little);
    }

    fn decode(allocator: Allocator, buf: []const u8) !WalRecord {
        const header_size = @sizeOf(RecordHeader);
        if (buf.len < header_size + @sizeOf(u32)) {
            return error.BufferTooSmall;
        }

        // Read header fields manually to match checksum computation
        const record_type: RecordType = @enumFromInt(buf[0]);
        const payload_len = std.mem.readInt(u32, buf[1..5], .little);
        const lsn = std.mem.readInt(u64, buf[5..13], .little);
        const timestamp = std.mem.readInt(u64, buf[13..21], .little);

        // Verify we have enough data
        const total_size = header_size + payload_len + @sizeOf(u32);
        if (buf.len < total_size) {
            return error.BufferTooSmall;
        }

        // Copy payload
        const payload = try allocator.dupe(u8, buf[header_size .. header_size + payload_len]);
        errdefer allocator.free(payload);

        // Read checksum
        const checksum = std.mem.readInt(u32, buf[header_size + payload_len .. header_size + payload_len + @sizeOf(u32)], .little);

        const record = WalRecord{
            .allocator = allocator,
            .record_type = record_type,
            .lsn = lsn,
            .timestamp = timestamp,
            .payload = payload,
            .checksum = checksum,
        };

        if (!record.verify()) {
            return error.ChecksumMismatch;
        }

        return record;
    }

    inline fn encodedSize(self: *const WalRecord) usize {
        return @sizeOf(RecordHeader) + self.payload.len + @sizeOf(u32);
    }
};

/// WAL Writer
const WalWriter = struct {
    allocator: Allocator,
    /// Base directory for WAL files
    base_dir: []u8,
    /// Current WAL file
    file: ?fs.File,
    /// Current WAL file path
    file_path: ?[]u8,
    /// Current file size
    file_size: usize,
    /// Current file number
    file_num: u64,
    /// Next log sequence number
    next_lsn: u64,

    fn init(allocator: Allocator, base_dir: []u8) !WalWriter {
        // Ensure base directory exists
        fs.cwd().makeDir(base_dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };

        // Create WAL directory if not exists
        const wal_dir = std.mem.concat(allocator, base_dir, "/wal");
        errdefer allocator.free(wal_dir);

        fs.cwd().makeDir(wal_dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };

        const base_dir_copy = allocator.dupe(u8, base_dir);

        return .{
            .allocator = allocator,
            .base_dir = base_dir_copy,
            .file = null,
            .file_path = null,
            .file_size = 0,
            .file_num = 0,
            .next_lsn = 1,
        };
    }

    fn deinit(self: *WalWriter) void {
        self.closeCurrentFile();
        self.allocator.free(self.base_dir);
    }

    fn closeCurrentFile(self: *WalWriter) void {
        if (self.file) |f| {
            // Sync before closing
            self.sync() catch {};
            f.close();
            self.file = null;
        }
        if (self.file_path) |path| {
            self.allocator.free(path);
            self.file_path = null;
        }
        self.file_size = 0;
    }

    /// Generate WAL file path
    fn makeWalPath(self: *const WalWriter, file_num: u64) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/wal/{:0>8}.wal", .{
            self.base_dir, file_num,
        });
    }

    /// Create WAL file
    fn createWalFile(self: *WalWriter) !void {
        self.closeCurrentFile();

        const path = try self.makeWalPath(self.file_num);
        errdefer self.allocator.free(path);

        const file = try fs.cwd().createFile(path, .{ .read = true });
        errdefer file.close();

        // Write WAL file header
        const header = WalFileHeader.init();
        try file.writeAll(&std.mem.asBytes(&header));

        // Sync to ensure header is on disk
        try file.sync();

        self.file = file;
        self.file_path = path;
        self.file_size = @sizeOf(WalFileHeader);
        self.file_num += 1;
    }

    /// Append a record to the WAL
    fn append(self: *WalWriter, record_type: RecordType, payload: []u8) !u64 {
        // Ensure we have an open WAL file
        if (self.file == null or self.file_size > WAL_MAX_FILE_SIZE) {
            if (self.file != null) {
                self.file_num += 1;
            }
            try self.createWalFile();
        }

        const lsn = self.next_lsn;

        const record = try WalRecord.init(self.allocator, record_type, lsn, payload);
        errdefer record.deinit();

        const encoded_size = record.encodedSize();
        const buf = try self.allocator.alloc(u8, encoded_size);
        errdefer self.allocator.free(buf);

        try record.encode(buf);

        // We should have an abstraction for file operations
        try self.file.?.writeAll(buf);
        self.file_size += encoded_size;
        self.next_lsn += 1;

        return lsn;
    }
};

/// WAL Manager
const WalManager = struct {
    allocator: Allocator,
    writer: WalWriter,

    fn init(allocator: Allocator, base_dir: []u8) !WalManager {
        const writer = try WalWriter.init(allocator, base_dir);
        return .{
            .allocator = allocator,
            .writer = writer,
        };
    }

    fn deinit(self: *WalManager) void {
        self.writer.deinit();
    }

    fn logPutVertex(self: *WalManager, vertex_id: []const u8, properties: ?[]const u8) !u64 {
        
    }
};
