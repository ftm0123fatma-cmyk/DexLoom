# DEX Support Matrix

## Opcode Coverage: All 256 Dalvik Opcodes

DexLoom implements **production-grade coverage of all 256 Dalvik opcodes** as defined in the
Android DEX format specification. This includes every instruction format, all arithmetic/logic
operations, array operations, comparisons, conversions, wide (64-bit) operations, switches,
fill-array-data (including 8-byte elements), monitor-enter/exit, throw, and all /range variants.

### Dispatch Method
- **Computed goto dispatch** (gcc/clang extension): 256-entry dispatch_table with per-opcode labels and DISPATCH_NEXT macro
- Switch fallback preserved for non-gcc/clang compilers

### Bytecode Verifier
DexLoom includes a two-pass structural bytecode verifier (`dx_verifier.c`):
- Branch targets validated against instruction boundary bitmap
- Register index bounds checking (all instruction formats)
- const-string, class, method, and field index bounds checking
- Switch and fill-array-data payload validation
- Code flow off-end detection
- Verification failures reported with actionable diagnostics

**Not yet implemented**: register type tracking through control flow, method signature validation at call sites, field type validation at access sites, exception handler range verification.

### Edge Cases Handled
- INT_MIN / -1 overflow in div-int and rem-int (returns INT_MIN / 0 respectively)
- Null operands in instance-of (returns 0) and check-cast (succeeds)
- Fill-array-data with 8-byte wide elements (long/double)
- Packed-switch and sparse-switch with full jump table parsing
- Finally block execution during exception unwinding
- NaN semantics in float/double comparisons

## Full Opcode Table

| Family | Opcodes | Status | Notes |
|--------|---------|--------|-------|
| nop | 0x00 | Real | |
| move | 0x01-0x09 | Real | All widths including /16 and wide |
| move-result | 0x0A-0x0D | Real | Including move-exception |
| return | 0x0E-0x11 | Real | void, int, wide, object |
| const | 0x12-0x1B | Real | All variants including const-wide (5 units) |
| const-string | 0x1A-0x1B | Real | Including /jumbo |
| const-class | 0x1C | Real | |
| monitor | 0x1D-0x1E | **Stub** | No threading model; monitor-enter/exit are no-ops |
| check-cast | 0x1F | Real | With class hierarchy + interface checking |
| instance-of | 0x20 | Real | With interface checking; null returns 0 |
| array-length | 0x21 | Real | |
| new-instance | 0x22 | Real | |
| new-array | 0x23 | Real | |
| filled-new-array | 0x24-0x25 | Real | 35c and 3rc formats |
| fill-array-data | 0x26 | Real | All element widths (1/2/4/8 bytes) |
| throw | 0x27 | Real | With catch handler search and cross-method unwinding |
| goto | 0x28-0x2A | Real | 8/16/32-bit offsets |
| switch | 0x2B-0x2C | Real | Packed and sparse with full payload parsing |
| cmp | 0x2D-0x31 | Real | float/double/long with NaN semantics |
| if-test | 0x32-0x37 | Real | eq, ne, lt, ge, gt, le |
| if-testz | 0x38-0x3D | Real | eqz, nez, ltz, gez, gtz, lez |
| reserved | 0x3E-0x43 | Default | Skipped by width |
| aget | 0x44-0x4A | Real | All 7 type variants |
| aput | 0x4B-0x51 | Real | All 7 type variants |
| iget | 0x52-0x58 | Real | All 7 type variants |
| iput | 0x59-0x5F | Real | All 7 type variants |
| sget | 0x60-0x66 | Real | All 7 type variants |
| sput | 0x67-0x6D | Real | All 7 type variants |
| invoke | 0x6E-0x72 | Real | virtual/super/direct/static/interface |
| reserved | 0x73 | Default | Skipped by width |
| invoke/range | 0x74-0x78 | Real | All 5 variants |
| reserved | 0x79-0x7A | Default | Skipped by width |
| unary | 0x7B-0x8F | Real | neg, not, int-to-*, float-to-*, double-to-*, long-to-* |
| binop | 0x90-0xAF | Real | add/sub/mul/div/rem/and/or/xor/shl/shr/ushr (int/long/float/double) |
| binop/2addr | 0xB0-0xCF | Real | All variants |
| binop/lit16 | 0xD0-0xD7 | Real | add/rsub/mul/div/rem/and/or/xor |
| binop/lit8 | 0xD8-0xE2 | Real | add/rsub/mul/div/rem/and/or/xor/shl/shr/ushr |
| reserved | 0xE3-0xF9 | Default | Skipped by width |
| invoke-polymorphic | 0xFA-0xFB | **Real** | MethodHandle.invoke/invokeExact with all 9 handle kinds |
| invoke-custom | 0xFC-0xFD | **Real** | LambdaMetafactory + StringConcatFactory |
| const-method-handle | 0xFE | **Real** | Wraps DxMethodHandle in DxObject |
| const-method-type | 0xFF | **Real** | Wraps DxDexProtoId in DxObject |

### invoke-custom Details
- Parses call_site_item from DEX (method_handle_item + encoded_array)
- Detects bootstrap method: LambdaMetafactory or StringConcatFactory
- **LambdaMetafactory**: generates synthetic DxClass with captured variables and native dispatch
- **StringConcatFactory**: interprets recipe string with \x01 placeholders for argument substitution

## Instruction Formats Supported

All DEX instruction formats are supported:

| Format | Description | Example Opcodes |
|--------|-------------|-----------------|
| 10x | op | nop, return-void |
| 10t | op +AA | goto |
| 11n | op vA, #+B | const/4 |
| 11x | op vAA | move-result, return, throw, monitor-* |
| 12x | op vA, vB | move, int-to-*, neg-*, not-* |
| 20t | op +AAAA | goto/16 |
| 21s | op vAA, #+BBBB | const/16, const-wide/16 |
| 21h | op vAA, #+BBBB0000 | const/high16, const-wide/high16 |
| 21t | op vAA, +BBBB | if-*z |
| 21c | op vAA, type/string@BBBB | const-string, new-instance, check-cast, etc. |
| 22x | op vAA, vBBBB | move/from16 |
| 22b | op vAA, vBB, #+CC | add-int/lit8, etc. |
| 22s | op vA, vB, #+CCCC | add-int/lit16, etc. |
| 22t | op vA, vB, +CCCC | if-eq, if-ne, if-lt, if-ge, if-gt, if-le |
| 22c | op vA, vB, field/type@CCCC | iget-*, iput-*, instance-of |
| 23x | op vAA, vBB, vCC | aget-*, aput-*, add-*, sub-*, cmp* |
| 30t | op +AAAAAAAA | goto/32 |
| 31i | op vAA, #+BBBBBBBB | const, const-wide/32 |
| 31c | op vAA, string@BBBBBBBB | const-string/jumbo |
| 31t | op vAA, +BBBBBBBB | fill-array-data, packed-switch, sparse-switch |
| 32x | op vAAAA, vBBBB | move/16 |
| 35c | op {vC..vG}, meth/type@BBBB | invoke-*, filled-new-array |
| 3rc | op {vCCCC..vNNNN}, meth@BBBB | invoke-*/range, filled-new-array/range |
| 45cc | op {vC..vG}, meth@BBBB, proto@HHHH | invoke-polymorphic |
| 4rcc | op {vCCCC..vNNNN}, meth@BBBB, proto@HHHH | invoke-polymorphic/range |
| 51l | op vAA, #+BBBBBBBBBBBBBBBB | const-wide |

## DEX Format Support

| Feature | Supported |
|---------|-----------|
| DEX version 035 | Yes |
| DEX version 037 | Yes |
| DEX version 038 | Yes |
| DEX version 039 | Yes |
| Multi-DEX loading | Yes (up to 8 DEX files) |
| Annotation parsing | Yes (type + visibility on class/method) |
| Debug info (line numbers) | Yes (binary search lookup via dx_method_get_line) |
| Encoded values (all types) | Yes (VALUE_ARRAY, VALUE_ANNOTATION, etc.) |
| Call site items | Yes (for invoke-custom) |
| Method handle items | Yes (for invoke-custom bootstrap) |
| Multidex | Yes |
| Compact DEX (CDEX) | No |
| VDEX container | No |
| OAT files | No |

## Interpreter Features

| Feature | Status |
|---------|--------|
| Exception try/catch/finally | Full support with cross-method unwinding |
| Varargs method invocation | Supported (pack_varargs) |
| Frame pooling | 64-frame pool, zero malloc per call |
| Class hash table | FNV-1a O(1) lookup (4096 buckets) |
| Null-safe type checks | instance-of returns false, check-cast passes |
| Computed goto dispatch | 256-entry table, DISPATCH_NEXT macro |
| Instruction budget | Per-call limit (500,000 instructions) with non-fatal exhaustion |
| invoke-custom | LambdaMetafactory + StringConcatFactory |
| invoke-polymorphic | MethodHandle.invoke/invokeExact, all 9 handle kinds (invoke-static/instance/direct/interface/constructor, iget/iput/sget/sput) |
| const-method-handle/type | Real DxMethodHandle/DxDexProtoId wrapping |
| Inline caching | 4-entry polymorphic IC per invoke-virtual call site, FIFO eviction |
| Method inlining | Trivial getters (iget+return) and setters (iput+return-void) bypass frame creation |
| Register file pinning | pinned_regs/pinned_code locals for interpreter hot path |
| Interface method table | O(1) itable dispatch with default methods and diamond resolution |
| Incremental GC | Mark stack + batched mark/sweep (256 objects/step) |
| Custom ClassLoader | PathClassLoader, DexClassLoader, URLClassLoader with loadClass/getParent |
| Bridge method handling | ACC_BRIDGE detection, non-bridge preferred |

## Debug & Profiling Infrastructure

| Feature | Details |
|---------|---------|
| Bytecode trace | Per-instruction logging with PC, opcode, register state; method prefix filter |
| Class load trace | Logs every class loaded with source DEX file index |
| Method call trace | Entry/exit logging with class, method name, depth, arg count |
| Method profiling | total_time_ns + call_count per method, gated by profiling_enabled |
| Opcode histogram | uint64_t[256] array, dx_vm_dump_opcode_stats() logs top 20 |
| Hot method identification | dx_vm_dump_hot_methods() sorts by total_time_ns |
| GC pause measurement | last_gc_pause_ns + total_gc_pause_ns, logged after each GC |
| Allocation tracking | total_allocations + total_bytes_allocated counters |
| Fuzzing harness | dx_fuzz_apk/dex/axml/resources entry points (libFuzzer-compatible) |

## Parser Hardening

| Threat | Mitigation |
|--------|------------|
| Path traversal in ZIP entries | Reject `../` in filenames |
| Zip bomb (decompression ratio) | Size limit checks (>100:1 ratio rejected) |
| Encrypted APK entries | General purpose bit flag detection with clear error |
| ZIP64 archives | EOCD Locator + ZIP64 EOCD for 8-byte entry count and cd_offset |
| Memory-mapped access | mmap/munmap for large APKs via dx_apk_open_file() |
| APK signatures | V2/V3 scheme detection via "APK Sig Block 42" magic |
| Split APKs | dx_apk_open_split() merges split entries into base |
| AXML recursion depth | Hard limit on nesting (100 levels) |
| AXML namespace | 3-tier resolution: namespace+name, resource ID, name-only fallback |
| DEX offset validation | Bounds-checked before every table access |
| DEX checksum | Adler32 validation via zlib adler32() over bytes 12..file_size |
| DEX signature | SHA-1 validation via CommonCrypto CC_SHA1 over bytes 32..file_size |
| DEX map section | map_list parsed into DxMapItem array |
| DEX hidden API | Version 039+ detection with warning log |
| Malformed bytecode | Structural verifier rejects invalid code |
| Register index overflow | CHECK_REG macro on all instruction formats |
| Code boundary overrun | Instruction boundary bitmap + CODE_AT macro |
| File system access | Sandbox root enforcement, /proc/sys/dev rejection |
| Crash isolation | SIGSEGV/SIGBUS signal handlers with sigsetjmp/siglongjmp recovery |
