const std = @import("std");
const tags = @import("../tags.zig");
const abi = @import("../abi.zig");

const RecordBatchError = error {
	NotStruct,
};

pub const BufferAlignment = abi.BufferAlignment;

// This exists to be able to nest arrays at runtime.
pub const Array = struct {
	tag: tags.Tag,
	name: []const u8,
	allocator: std.mem.Allocator,
	length: usize,
	null_count: usize,
	// https://arrow.apache.org/docs/format/Columnar.html#buffer-listing-for-each-layout
	// Depending on layout stores validity, type_ids, offets, data, or indices.
	// You can tell how many buffers there are by looking at `tag.abiLayout().nBuffers()`
	bufs: [3][]align(abi.BufferAlignment) u8,
	children: []*Array,

	const Self = @This();

	fn arrayRelease(arr: *abi.Array) callconv(.C) void {
		const self = @ptrCast(*Self, @alignCast(@alignOf(Self), arr.private_data));
		if (arr.buffers) |buffers| {
			self.allocator.free(buffers[0..@intCast(usize, arr.n_buffers)]);
		}
		if (arr.children) |children| {
			for (0..@intCast(usize, arr.n_children)) |i| {
				children[i].release.?(children[i]);
				self.allocator.destroy(children[i]);
			}
			self.allocator.free(children[0..@intCast(usize, arr.n_children)]);
		}
		if (arr.dictionary) |dictionary| {
			dictionary.release.?(dictionary);
			self.allocator.destroy(dictionary);
		}
		self.deinit2(false);
		arr.*.release = null;
	}

	pub fn init(allocator: std.mem.Allocator) !*Self {
		return try allocator.create(Self);
	}

	fn deinit2(self: *Self, comptime free_children: bool) void {
		if (free_children) {
			for (self.children) |c| {
				c.deinit();
			}
		}
		if (self.children.len > 0) {
			self.allocator.free(self.children);
		}

		for (self.bufs) |b| {
			if (b.len > 0) {
				self.allocator.free(b);
			}
		}
		self.allocator.destroy(self);
	}

	pub fn deinit(self: *Self) void {
		self.deinit2(true);
	}

	const BufferPtrs = std.meta.fieldInfo(abi.Array, .buffers).type;
	const BufferPtr = ?*align(abi.BufferAlignment) const anyopaque;

	fn abiBuffers(self: Self, n_buffers: usize) std.mem.Allocator.Error!BufferPtrs {
		if (n_buffers == 0) {
			return null;
		}

		const buffers = try self.allocator.alloc(BufferPtr, n_buffers);
		for (0..n_buffers) |i| {
			const b = self.bufs[i];
			buffers[i] = if (b.len > 0) @ptrCast(BufferPtr, b.ptr) else null;
		}

		return @ptrCast(BufferPtrs, buffers);
	}

	fn abiChildren(self: Self, n_children: usize) std.mem.Allocator.Error!?[*]*abi.Array {
		if (n_children == 0) {
			return null;
		}
		const children = try self.allocator.alloc(*abi.Array, n_children);
		for (0..n_children) |j| {
			children[j] = try self.allocator.create(abi.Array);
			children[j].* = try self.children[j].toOwnedAbi();
		}

		return @ptrCast(?[*]*abi.Array, children);
	}

	fn abiDictionary(self: Self, layout: abi.Array.Layout) std.mem.Allocator.Error!?*abi.Array {
		if (layout != .Dictionary) {
			return null;
		}

		var dictionary = try self.allocator.create(abi.Array);
		dictionary.* = try self.children[0].toOwnedAbi();

		return @ptrCast(?*abi.Array, dictionary);
	}

	pub fn toOwnedAbi(self: *Self) std.mem.Allocator.Error!abi.Array {
		const layout = self.tag.abiLayout();
		const n_buffers = layout.nBuffers();
		const n_children = if (layout == .Dictionary) 0 else self.children.len;

		return .{
			.length = @intCast(i64, self.length),
			.null_count = @intCast(i64, self.null_count),
			.offset = 0,
			.n_buffers = @intCast(i64, n_buffers),
			.n_children = @intCast(i64, n_children),
			.buffers = try self.abiBuffers(n_buffers),
			.children = try self.abiChildren(n_children),
			.dictionary = try self.abiDictionary(layout),
			.release = arrayRelease,
			.private_data = @ptrCast(?*anyopaque, self),
		};
	}

	fn schemaRelease(schema: *abi.Schema) callconv(.C) void {
		const self = @ptrCast(*Self, @alignCast(@alignOf(Self), schema.private_data));
		if (schema.children) |children| {
			for (0..@intCast(usize, schema.n_children)) |i| {
				children[i].release.?(children[i]);
				self.allocator.destroy(children[i]);
			}
			self.allocator.free(children[0..@intCast(usize, schema.n_children)]);
		}
		if (schema.dictionary) |dictionary| {
			dictionary.release.?(dictionary);
			self.allocator.destroy(dictionary);
		}
		if (schema.name) |n| {
			// TODO: maybe store this somewhere for faster frees?
			const len = std.mem.indexOfSentinel(u8, 0, n) + 1;
			self.allocator.free(n[0..len]);
		}
		if (self.tag.isAbiFormatOnHeap()) {
			// TODO: maybe store this somewhere for faster frees?
			const len = std.mem.indexOfSentinel(u8, 0, schema.format) + 1;
			self.allocator.free(schema.format[0..len]);
		}
		schema.*.release = null;
	}

	fn abiSchemaChildren(self: Self, n_children: usize) std.mem.Allocator.Error!?[*]*abi.Schema {
		if (n_children == 0) {
			return null;
		}
		const children = try self.allocator.alloc(*abi.Schema, n_children);
		for (0..n_children) |j| {
			children[j] = try self.allocator.create(abi.Schema);
			children[j].* = try self.children[j].ownedSchema();
		}

		return @ptrCast(?[*]*abi.Schema, children);
	}

	fn abiSchemaDictionary(self: Self, layout: abi.Array.Layout) std.mem.Allocator.Error!?*abi.Schema {
		if (layout != .Dictionary) {
			return null;
		}

		var dictionary = try self.allocator.create(abi.Schema);
		dictionary.* = try self.children[0].ownedSchema();

		return @ptrCast(?*abi.Schema, dictionary);
	}

	pub fn ownedSchema(self: *Self) std.mem.Allocator.Error!abi.Schema {
		const layout = self.tag.abiLayout();
		const n_children = if (layout == .Dictionary) 0 else self.children.len;

		return .{
			.format = try self.tag.abiFormat(self.allocator, n_children),
			.name = if (self.name.len == 0) null else try self.allocator.dupeZ(u8, self.name),
			.metadata = null,
			.flags = .{
				.nullable = self.tag.isNullable(),
			},
			.n_children = @intCast(i64, n_children),
			.children = try self.abiSchemaChildren(n_children),
			.dictionary = try self.abiSchemaDictionary(layout),
			.release = schemaRelease,
			.private_data = @ptrCast(?*anyopaque, self),
		};
	}

	pub fn toRecordBatch(self: *Self, name: []const u8) RecordBatchError!void {
		if (self.tag != .struct_) {
			return RecordBatchError.NotStruct;
		}
		// Record batches don't support nulls. It's ok to erase this because our struct impl saves null
		// info in the children arrays.
		// https://docs.rs/arrow-array/latest/arrow_array/array/struct.StructArray.html#comparison-with-recordbatch
		self.name = name;
		self.null_count = 0;
		self.tag.struct_.is_nullable = false;
		self.allocator.free(self.bufs[0]); // Free some memory.
		self.bufs[0].len = 0; // Avoid double free.
	}

	fn print2(self: *Self, depth: u8) void {
		const tab = (" " ** std.math.maxInt(u8))[0..depth*2];
		std.debug.print("{s}Array \"{s}\": {any}\n", .{ tab, self.name, self.tag });
		std.debug.print("{s}  null_count: {d} / {d}\n", .{ tab, self.null_count, self.length });
		std.debug.print("{s}  bufs: ", .{ tab });
		for (self.bufs) |b| {
			std.debug.print("{d} ", .{ b.len });
		}
		std.debug.print("\n", .{});
		for (self.children) |c| {
			c.print2(depth + 1);
		}
	}

	pub fn print(self: *Self) void {
		self.print2(0);
	}
};

const MaskInt = std.bit_set.DynamicBitSet.MaskInt;

fn numMasks(comptime T: type, bit_length: usize) usize {
	return (bit_length + (@bitSizeOf(T) - 1)) / @bitSizeOf(T);
}

pub fn validity(
	allocator: std.mem.Allocator,
	bit_set: *std.bit_set.DynamicBitSet,
	null_count: usize
) ![]align(BufferAlignment) u8 {
	// Have to copy out for alignment until aligned bit masks land in std :(
	// https://github.com/ziglang/zig/issues/15600
	if (null_count == 0) {
		bit_set.deinit();
		return &.{};
	}
	const n_masks = numMasks(MaskInt, bit_set.unmanaged.bit_length);
	const n_mask_bytes = numMasks(u8, bit_set.unmanaged.bit_length);

	const copy = try allocator.alignedAlloc(u8, BufferAlignment, n_mask_bytes);
	const maskInts = bit_set.unmanaged.masks[0..n_masks];
	@memcpy(copy, std.mem.sliceAsBytes(maskInts)[0..n_mask_bytes]);
	bit_set.deinit();

	return copy;
}

// Dummy allocator
fn alloc(_: *anyopaque, _: usize, _: u8, _: usize) ?[*]u8 { return null; }
fn resize(_: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool { return false; }
fn free(_: *anyopaque, _: []u8, _: u8, _: usize) void {}

pub const null_array = Array {
	.tag = .null,
	.name = &.{},
	.allocator = std.mem.Allocator {
		.ptr = undefined,
		.vtable = &std.mem.Allocator.VTable {
			.alloc = alloc,
			.resize = resize,
			.free = free,
		}
	},
	.length = 0,
	.null_count = 0,
	.bufs = .{ &.{}, &.{}, &.{} },
	.children = &.{},
};

test "null array" {
	var n = null_array;
	try std.testing.expectEqual(@as(usize, 0), n.null_count);
}

test "null array abi" {
	var n = null_array;
	const c = try n.toOwnedAbi();
	defer c.release.?(@constCast(&c));
	try std.testing.expectEqual(@as(i64, 0), c.null_count);

	const s = try n.ownedSchema();
	defer s.release.?(@constCast(&s));
	try std.testing.expectEqualStrings("n\x00", s.format[0..2]);
	try std.testing.expectEqual(@as(i64, 0), s.n_children);
}
