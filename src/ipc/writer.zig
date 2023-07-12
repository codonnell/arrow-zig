const std = @import("std");
const flatbuffers = @import("flatbuffers");
const tags = @import("../tags.zig");
const Array = @import("../array/array.zig").Array;
const shared = @import("shared.zig");
const TypeId = @import("../array/union.zig").TypeId;
const flat = @import("./gen/lib.zig");

const log = shared.log;
const Allocator = std.mem.Allocator;
const FieldNode = flat.FieldNode;
const Message = flat.Message;
const Buffer = flat.Buffer;
const Block = flat.Block;
const Schema = flat.Schema;
const IpcError = error{
    ArrayNotDictionary,
} || shared.IpcError;

fn getFieldNodes(accumulator: *std.ArrayList(FieldNode), array: *Array) !void {
    try accumulator.append(FieldNode{
        .length = @bitCast(array.length),
        .null_count = @bitCast(array.null_count),
    });
    if (array.tag != .Dictionary) for (array.children) |c| try getFieldNodes(accumulator, c);
}

test "getFieldNodes root" {
    const allocator = std.testing.allocator;
    const batch = try sample.all(allocator);
    defer batch.deinit();

    var nodes = std.ArrayList(FieldNode).init(allocator);
    defer nodes.deinit();
    for (batch.children) |c| try getFieldNodes(&nodes, c);

    const expected_fields = &[_]FieldNode{
        .{ .length = 4, .null_count = 1 },
        .{ .length = 4, .null_count = 1 },
        .{ .length = 12, .null_count = 0 },
        .{ .length = 4, .null_count = 1 },
        .{ .length = 4, .null_count = 1 },
        .{ .length = 9, .null_count = 0 },
        .{ .length = 4, .null_count = 1 },
        .{ .length = 12, .null_count = 0 },
        .{ .length = 4, .null_count = 1 },
        .{ .length = 4, .null_count = 2 },
        .{ .length = 4, .null_count = 1 },
        .{ .length = 4, .null_count = 0 },
        .{ .length = 3, .null_count = 1 },
        .{ .length = 1, .null_count = 0 },
        .{ .length = 4, .null_count = 0 },
        .{ .length = 4, .null_count = 2 },
        .{ .length = 4, .null_count = 3 },
        .{ .length = 4, .null_count = 1 },
        .{ .length = 4, .null_count = 1 },
        .{ .length = 4, .null_count = 0 },
        .{ .length = 4, .null_count = 0 },
        .{ .length = 4, .null_count = 1 },
    };

    const schema = try Schema.initFromArray(allocator, batch);
    defer schema.deinit(allocator);
    const n_fields = schema.nFields();
    try std.testing.expectEqual(expected_fields.len, n_fields);

    try std.testing.expectEqualSlices(FieldNode, expected_fields, nodes.items);
}

test "getBuffers dict" {
    const allocator = std.testing.allocator;
    const dict = try sample.dict(allocator);
    defer dict.deinit();

    var buffers = std.ArrayList(Buffer).init(allocator);
    defer buffers.deinit();
    _ = try writeBuffers(dict.children[0], void, &buffers);

    const expected_buffers = &[_]Buffer{
        .{ .offset = 0, .length = 0 },
        .{ .offset = 0, .length = 16 },
        .{ .offset = 16, .length = 16 },
    };

    const schema = try Schema.initFromArray(allocator, dict);
    defer schema.deinit(allocator);
    const n_buffers = try schema.nBuffers();
    try std.testing.expectEqual(expected_buffers.len, n_buffers);

    try std.testing.expectEqualSlices(Buffer, expected_buffers, buffers.items);
}

test "getBuffers root" {
    const allocator = std.testing.allocator;
    const batch = try sample.all(allocator);
    defer batch.deinit();

    var buffers = std.ArrayList(Buffer).init(allocator);
    defer buffers.deinit();

    for (batch.children) |c| _ = try writeBuffers(c, void, &buffers);

    const expected_buffers = &[_]Buffer{
        .{ .offset = 0, .length = 1 },
        .{ .offset = 8, .length = 8 },
        .{ .offset = 16, .length = 1 },
        .{ .offset = 24, .length = 0 },
        .{ .offset = 24, .length = 24 },
        .{ .offset = 48, .length = 1 },
        .{ .offset = 56, .length = 20 },
        .{ .offset = 80, .length = 18 },
        .{ .offset = 104, .length = 1 },
        .{ .offset = 112, .length = 20 },
        .{ .offset = 136, .length = 0 },
        .{ .offset = 136, .length = 18 },
        .{ .offset = 160, .length = 1 },
        .{ .offset = 168, .length = 0 },
        .{ .offset = 168, .length = 24 },
        .{ .offset = 192, .length = 1 },
        .{ .offset = 200, .length = 1 },
        .{ .offset = 208, .length = 16 },
        .{ .offset = 224, .length = 1 },
        .{ .offset = 232, .length = 32 },
        .{ .offset = 264, .length = 4 },
        .{ .offset = 272, .length = 16 },
        .{ .offset = 288, .length = 1 },
        .{ .offset = 296, .length = 12 },
        .{ .offset = 312, .length = 0 },
        .{ .offset = 312, .length = 4 },
        .{ .offset = 320, .length = 4 },
        .{ .offset = 328, .length = 1 },
        .{ .offset = 336, .length = 16 },
        .{ .offset = 352, .length = 1 },
        .{ .offset = 360, .length = 16 },
        .{ .offset = 376, .length = 1 },
        .{ .offset = 384, .length = 4 },
        .{ .offset = 392, .length = 1 },
        .{ .offset = 400, .length = 20 },
        .{ .offset = 424, .length = 0 },
        .{ .offset = 424, .length = 0 },
        .{ .offset = 424, .length = 20 },
        .{ .offset = 448, .length = 20 },
        .{ .offset = 472, .length = 1 },
        .{ .offset = 480, .length = 16 },
    };

    const schema = try Schema.initFromArray(allocator, batch);
    defer schema.deinit(allocator);
    const n_buffers = try schema.nBuffers();
    try std.testing.expectEqual(expected_buffers.len, n_buffers);

    try std.testing.expectEqualSlices(Buffer, expected_buffers, buffers.items);
}

inline fn getPadding(n: usize) usize {
    // Pad to nearest 8 byte boundary because that's what existing files do...
    const mod = @mod(n, 8);
    if (mod != 0) return 8 - mod;
    return 0;
}

fn writeBuffers(
    array: *Array,
    writer_: anytype,
    accumulator: ?*std.ArrayList(Buffer),
) !usize {
    const commit = @typeInfo(@TypeOf(writer_)) == .Struct;

    var res: usize = 0;

    for (0..array.tag.abiLayout().nBuffers()) |i| {
        const b = array.buffers[i];
        if (commit) try writer_.writeAll(b);
        res += b.len;
        const n_padding = getPadding(b.len);
        res += n_padding;
        if (commit) for (0..n_padding) |_| try writer_.writeByte(0);

        if (accumulator) |a| {
            var offset = brk: {
                if (a.items.len == 0) break :brk 0;
                const last = a.getLast();
                const padding: i64 = @bitCast(getPadding(@bitCast(last.length)));
                break :brk last.offset + last.length + padding;
            };
            try a.append(Buffer{
                .offset = offset,
                .length = @bitCast(b.len),
            });
        }
    }
    if (array.tag != .Dictionary) {
        for (array.children) |c| res += try writeBuffers(c, writer_, accumulator);
    }
    return res;
}

pub fn Writer(comptime WriterType: type) type {
    return struct {
        const Self = @This();
        const Writer_ = std.io.CountingWriter(WriterType);

        allocator: Allocator,
        dest: Writer_,
        dict_id: i64 = 0,

        pub fn init(allocator: Allocator, dest: WriterType) !Self {
            return .{
                .allocator = allocator,
                .dest = std.io.countingWriter(dest),
            };
        }

        /// Writes a message and returns the offset to after the message len
        fn writeMessage(self: *Self, message: Message) !usize {
            var builder = flatbuffers.Builder.init(self.allocator);
            errdefer builder.deinit();
            const offset = try message.pack(&builder);
            const bytes = try builder.finish(offset);
            defer self.allocator.free(bytes);

            const len: shared.MessageLen = @intCast(bytes.len);
            try self.dest.writer().writeIntLittle(shared.MessageLen, len);
            const res = self.dest.bytes_written;
            try self.dest.writer().writeAll(bytes);

            return res;
        }

        /// Writes a schema message
        pub fn writeSchema(self: *Self, array: *Array) !Block {
            const message = Message{
                .header = .{ .schema = try Schema.initFromArray(self.allocator, array) },
                .body_length = 0,
                .custom_metadata = &.{},
            };
            defer message.deinit(self.allocator);

            return .{
                .offset = @bitCast(try self.writeMessage(message)),
                .meta_data_length = 0,
                .body_length = 0,
            };
        }

        /// Caller owns returned message
        fn getRecordBatch(self: *Self, array: *Array) !flat.RecordBatch {
            const schema = try Schema.initFromArray(self.allocator, array);
            defer schema.deinit(self.allocator);
            const n_fields = schema.nFields();
            const n_buffers = try schema.nBuffers();

            var nodes = try std.ArrayList(FieldNode).initCapacity(self.allocator, n_fields);
            errdefer nodes.deinit();
            for (array.children) |c| try getFieldNodes(&nodes, c);
            // for (nodes.items) |n| log.debug("write {any}", .{n});
            std.debug.assert(nodes.items.len == n_fields);

            var buffers = try std.ArrayList(Buffer).initCapacity(self.allocator, n_buffers);
            errdefer buffers.deinit();
            for (array.children) |c| _ = try writeBuffers(c, void, &buffers);
            // for (buffers.items) |n| log.debug("write {any}", .{n});
            std.debug.assert(buffers.items.len == n_buffers);

            return .{
                .length = @bitCast(array.length),
                .nodes = try nodes.toOwnedSlice(),
                .buffers = try buffers.toOwnedSlice(),
            };
        }

        /// Writes a record batch message
        pub fn writeBatch(self: *Self, array: *Array) !Block {
            const body_length = try writeBuffers(array, void, null);
            const message = Message{
                .header = .{ .record_batch = try self.getRecordBatch(array) },
                .body_length = @bitCast(body_length),
                .custom_metadata = &.{},
            };
            defer message.deinit(self.allocator);

            const offset = try self.writeMessage(message);
            _ = try writeBuffers(array, self.dest.writer(), null);

            return .{
                .offset = @bitCast(offset),
                .meta_data_length = 0,
                .body_length = message.body_length,
            };
        }

        /// Writes a dictionary batch message
        pub fn writeDict(self: *Self, array: *Array) !Block {
            if (array.tag != .Dictionary) {
                log.warn("called writeDict on non-dictionary array {s}", .{array.name});
                return IpcError.ArrayNotDictionary;
            }
            const record_batch_message = try self.getRecordBatch(array);
            // for (record_batch_message.nodes) |n| log.debug("write dict {any}", .{n});
            // for (record_batch_message.buffers) |n| log.debug("write dict {any}", .{n});
            const dict = array.children[0];
            const body_length = try writeBuffers(dict, void, null);
            const message = Message{
                .header = .{ .dictionary_batch = flat.DictionaryBatch{
                    .id = self.dict_id,
                    .data = record_batch_message,
                    .is_delta = false,
                } },
                .body_length = @bitCast(body_length),
                .custom_metadata = &.{},
            };
            defer message.deinit(self.allocator);

            const offset = try self.writeMessage(message);
            _ = try writeBuffers(dict, self.dest.writer(), null);
            self.dict_id += 1;

            return .{
                .offset = @bitCast(offset),
                .meta_data_length = 0,
                .body_length = message.body_length,
            };
        }
    };
}

fn BufferedWriter(comptime WriterType: type) type {
    return std.io.BufferedWriter(4096, WriterType);
}

pub fn writer(
    allocator: Allocator,
    writer_: anytype,
) !Writer(BufferedWriter(@TypeOf(writer_))) {
    var buffered = std.io.bufferedWriter(writer_);
    return Writer(BufferedWriter(@TypeOf(writer_))).init(allocator, buffered);
}

/// Handles file header and footer. Convienently closes file in .deinit.
const FileWriter = struct {
    const Self = @This();
    const WriterType = Writer(BufferedWriter(std.fs.File.Writer));
    const BlockList = std.ArrayList(Block);

    allocator: Allocator,
    file: std.fs.File,
    writer: WriterType,

    fn writeMagic(self: *Self, comptime is_start: bool) !void {
        try self.writer.dest.writer().writeAll(shared.magic);
        if (is_start) try self.writer.dest.writer().writeAll("\x00" ** (8 - shared.magic.len));
    }

    pub fn init(allocator: Allocator, fname: []const u8) !Self {
        var file = try std.fs.cwd().createFile(fname, .{});
        var res = Self{
            .allocator = allocator,
            .file = file,
            .writer = try writer(allocator, file.writer()),
        };
        try res.writeMagic(true);

        return res;
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    /// Caller owns returned slice
    fn getFooter(
        self: *Self,
        array: *Array,
        dictionaries: []Block,
        record_batches: []Block,
    ) ![]const u8 {
        const schema = try Schema.initFromArray(self.allocator, array);
        defer schema.deinit(self.allocator);
        const footer = flat.Footer{
            .schema = schema,
            .dictionaries = dictionaries,
            .record_batches = record_batches,
            .custom_metadata = &.{},
        };
        var builder = flatbuffers.Builder.init(self.allocator);
        errdefer builder.deinit();
        const offset = try footer.pack(&builder);
        return try builder.finish(offset);
    }

    fn writeDicts(self: *Self, acc: *BlockList, array: *Array) !void {
        if (array.tag == .Dictionary) {
            const block = try self.writer.writeDict(array);
            try acc.append(block);
        }
        for (array.children) |c| try self.writeDicts(acc, c);
    }

    pub fn write(self: *Self, array: *Array) !void {
        _ = try self.writer.writeSchema(array);

        var dictionaries = BlockList.init(self.allocator);
        defer dictionaries.deinit();
        try self.writeDicts(&dictionaries, array);

        var record_batch = try self.writer.writeBatch(array);

        const footer = try self.getFooter(
            array,
            dictionaries.items,
            @constCast(&[_]Block{record_batch}),
        );
        defer self.allocator.free(footer);
        try self.writer.dest.writer().writeAll(footer);

        var file = try std.fs.cwd().createFile("./footer.bfbs", .{});
        defer file.close();
        try file.writeAll(footer);

        const len: shared.MessageLen = @intCast(footer.len);
        try self.writer.dest.writer().writeIntLittle(shared.MessageLen, len);

        try self.writeMagic(false);

        try self.writer.dest.child_stream.flush();
        try self.file.sync();
    }
};

pub fn fileWriter(allocator: Allocator, fname: []const u8) !FileWriter {
    return FileWriter.init(allocator, fname);
}

const reader = @import("./reader.zig");
const sample = @import("../sample.zig");

test "write and read sample file" {
    const fname = "./sample2.arrow";
    const batch = try sample.all(std.testing.allocator);
    try batch.toRecordBatch("record batch");
    defer batch.deinit();

    var ipc_writer = try fileWriter(std.testing.allocator, fname);
    defer ipc_writer.deinit();

    try ipc_writer.write(batch);

    var ipc_reader = try reader.fileReader(std.testing.allocator, fname);
    defer ipc_reader.deinit();
    var n_batches: usize = 0;
    while (try ipc_reader.nextBatch()) |rb| {
        defer rb.deinit();
        try reader.testEquals(batch, rb);
        n_batches += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), n_batches);
}
