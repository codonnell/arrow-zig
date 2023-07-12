//! generated by flatc-zig from Schema.fbs

const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");
const Array = @import("../../array/array.zig").Array;

const Allocator = std.mem.Allocator;

/// ----------------------------------------------------------------------
/// Top-level Type value, enabling extensible type-specific metadata. We can
/// add new logical types to Type without breaking backwards compatibility
pub const Type = union(PackedType.Tag) {
    none,
    null: types.Null,
    int: types.Int,
    floating_point: types.FloatingPoint,
    binary: types.Binary,
    utf8: types.Utf8,
    bool: types.Bool,
    decimal: types.Decimal,
    date: types.Date,
    time: types.Time,
    timestamp: types.Timestamp,
    interval: types.Interval,
    list: types.List,
    struct_: types.Struct,
    @"union": types.Union,
    fixed_size_binary: types.FixedSizeBinary,
    fixed_size_list: types.FixedSizeList,
    map: types.Map,
    duration: types.Duration,
    large_binary: types.LargeBinary,
    large_utf8: types.LargeUtf8,
    large_list: types.LargeList,
    run_end_encoded: types.RunEndEncoded,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedType) flatbuffers.Error!Self {
        return switch (packed_) {
            .none => .none,
            .null => .{ .null = .{} },
            .int => |t| .{ .int = try types.Int.init(t) },
            .floating_point => |t| .{ .floating_point = try types.FloatingPoint.init(t) },
            .binary => .{ .binary = .{} },
            .utf8 => .{ .utf8 = .{} },
            .bool => .{ .bool = .{} },
            .decimal => |t| .{ .decimal = try types.Decimal.init(t) },
            .date => |t| .{ .date = try types.Date.init(t) },
            .time => |t| .{ .time = try types.Time.init(t) },
            .timestamp => |t| .{ .timestamp = try types.Timestamp.init(allocator, t) },
            .interval => |t| .{ .interval = try types.Interval.init(t) },
            .list => .{ .list = .{} },
            .struct_ => .{ .struct_ = .{} },
            .@"union" => |t| .{ .@"union" = try types.Union.init(allocator, t) },
            .fixed_size_binary => |t| .{ .fixed_size_binary = try types.FixedSizeBinary.init(t) },
            .fixed_size_list => |t| .{ .fixed_size_list = try types.FixedSizeList.init(t) },
            .map => |t| .{ .map = try types.Map.init(t) },
            .duration => |t| .{ .duration = try types.Duration.init(t) },
            .large_binary => .{ .large_binary = .{} },
            .large_utf8 => .{ .large_utf8 = .{} },
            .large_list => .{ .large_list = .{} },
            .run_end_encoded => .{ .run_end_encoded = .{} },
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        switch (self) {
            .timestamp => {
                self.timestamp.deinit(allocator);
            },
            .@"union" => {
                self.@"union".deinit(allocator);
            },
            else => {},
        }
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        switch (self) {
            inline else => |v| {
                if (comptime flatbuffers.isScalar(@TypeOf(v))) {
                    try builder.prepend(v);
                    return builder.offset();
                }
                return try v.pack(builder);
            },
        }
    }

    pub fn initFromArray(allocator: Allocator, array: *Array) Allocator.Error!Self {
        return switch (array.tag) {
            .Null => .null,
            .Bool => .bool,
            .Int => |i| .{ .int = .{
                .bit_width = switch (i.bit_width) {
                    ._8 => 8,
                    ._16 => 16,
                    ._32 => 32,
                    ._64 => 64,
                },
                .is_signed = i.signed,
            } },
            .Float => |f| .{ .floating_point = .{
                .precision = switch (f.bit_width) {
                    ._16 => .half,
                    ._32 => .single,
                    ._64 => .double,
                },
            } },
            .Date => |d| .{ .date = .{
                .unit = switch (d.unit) {
                    .day => .day,
                    .millisecond => .millisecond,
                },
            } },
            .Time => |t| .{ .time = .{
                .unit = switch (t.unit) {
                    .second => .second,
                    .millisecond => .millisecond,
                    .microsecond => .microsecond,
                    .nanosecond => .nanosecond,
                },
                .bit_width = switch (t.unit) {
                    .second, .millisecond => 32,
                    .microsecond, .nanosecond => 64,
                },
            } },
            .Timestamp => |t| .{ .timestamp = .{
                .unit = switch (t.unit) {
                    .second => .second,
                    .millisecond => .millisecond,
                    .microsecond => .microsecond,
                    .nanosecond => .nanosecond,
                },
                .timezone = t.timezone,
            } },
            .Duration => |d| .{ .duration = .{
                .unit = switch (d.unit) {
                    .second => .second,
                    .millisecond => .millisecond,
                    .microsecond => .microsecond,
                    .nanosecond => .nanosecond,
                },
            } },
            .Interval => |i| .{ .interval = .{
                .unit = switch (i.unit) {
                    .year_month => .year_month,
                    .day_time => .day_time,
                    .month_day_nanosecond => .month_day_nano,
                },
            } },
            .Binary => |b| {
                if (b.utf8) return if (b.large) .large_utf8 else .utf8;
                return if (b.large) .large_binary else .binary;
            },
            .FixedBinary => |f| .{ .fixed_size_binary = .{ .byte_width = f.fixed_len } },
            .List => |l| if (l.large) .large_list else .list,
            .FixedList => |f| .{ .fixed_size_list = .{ .list_size = f.fixed_len } },
            .Struct => .struct_,
            .Union => |u| .{ .@"union" = .{
                .mode = if (u.dense) .dense else .sparse,
                .type_ids = brk: {
                    const len = array.children.len;
                    var res = try std.ArrayList(i32).initCapacity(allocator, len);
                    for (0..len) |i| try res.append(@intCast(i));
                    break :brk try res.toOwnedSlice();
                },
            } },
            .Map => .{ .map = .{ .keys_sorted = false } },
            .Dictionary => try initFromArray(allocator, array.children[0]),
        };
    }
};

/// ----------------------------------------------------------------------
/// Top-level Type value, enabling extensible type-specific metadata. We can
/// add new logical types to Type without breaking backwards compatibility
pub const PackedType = union(enum) {
    none,
    null: types.PackedNull,
    int: types.PackedInt,
    floating_point: types.PackedFloatingPoint,
    binary: types.PackedBinary,
    utf8: types.PackedUtf8,
    bool: types.PackedBool,
    decimal: types.PackedDecimal,
    date: types.PackedDate,
    time: types.PackedTime,
    timestamp: types.PackedTimestamp,
    interval: types.PackedInterval,
    list: types.PackedList,
    struct_: types.PackedStruct,
    @"union": types.PackedUnion,
    fixed_size_binary: types.PackedFixedSizeBinary,
    fixed_size_list: types.PackedFixedSizeList,
    map: types.PackedMap,
    duration: types.PackedDuration,
    large_binary: types.PackedLargeBinary,
    large_utf8: types.PackedLargeUtf8,
    large_list: types.PackedLargeList,
    run_end_encoded: types.PackedRunEndEncoded,

    pub const Tag = std.meta.Tag(@This());
};
