# arrow-zig

![zig-version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fclickingbuttons%2Farrow-zig%2Fmaster%2F.github%2Fworkflows%2Ftest.yml&query=%24.jobs.test.steps%5B1%5D.with.version&label=zig-version)
![tests](https://github.com/clickingbuttons/arrow-zig/actions/workflows/test.yml/badge.svg)

Library to build Arrow arrays from Zig primitives and read/write them to FFI and IPC formats.

## Installation

`build.zig.zon`
```zig
.{
    .name = "yourProject",
    .version = "0.0.1",

    .dependencies = .{
        .@"arrow-zig" = .{
            .url = "https://github.com/clickingbuttons/arrow-zig/archive/refs/tags/latest-release.tar.gz",
        },
    },
}
```

`build.zig`
```zig
const arrow_dep = b.dependency("arrow-zig", .{
    .target = target,
    .optimize = optimize,
});
your_lib_or_exe.addModule("arrow", arrow_dep.module("arrow"));
```

Run `zig build` and then copy the expected hash into `build.zig.zon`.

## Usage

Arrow has [11 different array types](https://arrow.apache.org/docs/format/Columnar.html#buffer-listing-for-each-layout). Here's how arrow-zig maps them to Zig types.

| Arrow type            | Zig type                                            | arrow-zig builder |
|-----------------------|-----------------------------------------------------|-------------------|
| Primitive             | i8, i16, i32, i64, u8, u16, u32, u64, f16, f32, f64 | flat              |
| Variable binary       | []u8, []const u8                                    | flat              |
| List                  | []T                                                 | list              |
| Fixed-size list       | [N]T                                                | list              |
| Struct                | struct                                              | struct            |
| Dense union (default) | union                                               | union             |
| Sparse union          | union                                               | union             |
| Null                  | void                                                | Array.null_array  |
| Dictionary            | T                                                   | dictionary        |
| Map                   | struct { T, V }, struct { T, ?V }                   | map               |
| Run-end encoded       | N/A                                                 | N/A               |

Notes:

1. Run-end encoded array compression can be acheived by LZ4. Use that instead.
2. There is currently no Decimal type or library in Zig. Once added it will be a primitive.

### Build arrays

The default `Builder` can map Zig types with reasonable defaults except for Dictionary types. You can use it like this:
```zig
var b = try Builder(?i16).init(allocator);
try b.append(null);
try b.append(32);
try b.append(33);
try b.append(34);
```

Null-safety is preserved at compile time.
```zig
var b = try Builder(i16).init(allocator);
try b.append(null);
```
...
```
error: expected type 'i16', found '@TypeOf(null)'
    try b.append(null);
```

Dictionary types must use an explicit builder.
```zig
var b = try DictBuilder(?[]const u8).init(allocator);
try b.appendNull();
try b.append("hello");
try b.append("there");
try b.append("friend");
```

You can customize exactly how to build Arrow types with each type's `BuilderAdvanced`. For example to build a sparse union of nullable structs:
```zig
var b = try UnionBuilder(
    struct {
        f: Builder(?f32),
        i: Builder(?i32),
    },
    .{ .nullable = true, .dense = false },
    void,
).init(allocator);
try b.append(null);
try b.append(.{ .f = 1 });
try b.append(.{ .f = 3 });
try b.append(.{ .i = 5 });
```

You can view [sample.zig](./src/sample.zig) which has examples for all supported types.

### FFI

Arrow has a [C ABI](https://arrow.apache.org/docs/format/CDataInterface.html) that allows importing and exporting arrays over an FFI boundary by only copying metadata.

#### Export

If you have a normal `Array` you can export it to a `abi.Schema` and `abi.Array` to share the memory with other code (i.e. scripting languages). When you do so, that code is responsible for calling `abi.Schema.release(&schema)` and `abi.Array.release(&array)` to free memory.

```zig
const array = try arrow.sample.all(allocator);
errdefer array.deinit();

// Note: these are stack allocated.
var abi_arr = try abi.Array.init(array);
var abi_schema = try abi.Schema.init(array);

externFn(&abi_schema, &abi_arr);
```

#### Import

If you have a `abi.Schema` and `abi.Array` you can transform them to an `ImportedArray` that contains a normal `Array`. Be a good steward and free the memory with `imported.deinit()`.

```zig
const array = try arrow.sample.all(allocator);

var abi_schema = try abi.Schema.init(array);
var abi_arr = try abi.Array.init(array);
var imported = try arrow.ffi.ImportedArray.init(allocator, abi_arr, abi_schema);
defer imported.deinit();
```

### IPC

Array has a streaming [IPC format](https://arrow.apache.org/docs/format/Columnar.html#serialization-and-interprocess-communication-ipc) to transfer Arrays with zero-copy (unless you add compression or require different alignment). It has a [file format](https://github.com/apache/arrow/blob/main/format/File.fbs) as well.

Before using it over CSV, beware that:

1. There have been 5 versions of the format, mostly undocumented, with multiple breaking changes.
2. Although designed for streaming, most implementations buffer all messages. This means if you want to use other tools like `pyarrow` file sizes must remain small enough to fit in memory.
3. Size savings compared to CSV are marginal after compression.
4. If an array's buffer uses compression then reading is NOT zero-copy. Additionally, this implementation will have to copy misaligned data in order to align it. The C++ implementation uses 8 byte alignment while this implementation uses [the spec's recommended 64 byte alignment](https://arrow.apache.org/docs/format/Columnar.html#buffer-alignment-and-padding).
5. The message custom metadata that would make the format more useful for querying is inaccessible in most implementations, including this one.
6. Existing implementations do not support reading/writing record batches with different schemas.

This implementation is most useful as a way  to dump normal `Array`s to disk for later inspection.

#### Read

You can read record batches out of an existing Arrow file with `ipc.reader.fileReader`:

```zig
const ipc = @import("arrow").ipc;
var ipc_reader = try ipc.reader.fileReader(allocator, "./testdata/tickers.arrow");
defer ipc_reader.deinit();

while (try ipc_reader.nextBatch()) |rb| {
    // Do something with rb
    defer rb.deinit();
}
```

You can read from other streams via `ipc.reader.Reader(YourReaderType)`.

#### Write

You can write a struct `arrow.Array` to record batches with `ipc.writer.fileWriter`:

```zig
const batch = try arrow.sample.all(std.testing.allocator);
try batch.toRecordBatch("record batch");
defer batch.deinit();

const fname = "./sample.arrow";
var ipc_writer = try ipc.writer.fileWriter(std.testing.allocator, fname);
defer ipc_writer.deinit();
try ipc_writer.write(batch);
try ipc_writer.finish();
```

You can write to other streams via `ipc.writer.Writer(YourWriterType)`.
