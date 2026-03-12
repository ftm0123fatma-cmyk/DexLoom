# DexLoom Roadmap

## Milestone Plan

### Milestone 0: Feasibility Analysis -- ACHIEVED
- Architecture comparison document
- iOS platform constraint analysis
- Chosen approach: DEX bytecode interpreter + mini framework

### Milestone 1: APK Parsing and Inspection -- ACHIEVED
- ZIP file format parser (PKZIP) with hardening (path traversal, zip bomb)
- Entry enumeration and extraction (STORE + DEFLATE)
- Identify classes.dex, AndroidManifest.xml, resources.arsc, res/
- **Delivered**: Full APK content listing and extraction

### Milestone 2: AndroidManifest.xml and resources.arsc Decoding -- ACHIEVED
- Android Binary XML (AXML) parser with depth limits
- String pool, resource map, namespace handling
- Manifest parsing: package name, main activity, permissions
- Intent-filter details, meta-data, uses-feature, uses-library, exported flag
- resources.arsc: string pool, type specs, entries, dimension decoding
- Style/theme resolution with parent chain traversal
- Qualifier system (locale, density, orientation, SDK level, night mode, screen size)
- Array resources, plural resources, TypedArray
- **Delivered**: Full manifest and resource decoding with theme/style resolution

### Milestone 3: DEX Parsing -- ACHIEVED
- DEX header validation (magic, checksum, versions 035-039)
- All ID tables: string, type, proto, field, method
- Class definitions with annotations (type + visibility)
- Code items with bytecode, debug info (line number tables)
- Encoded values: VALUE_ARRAY, VALUE_ANNOTATION, all types
- Multi-DEX loading (up to 8 DEX files)
- Call site items and method handle items (for invoke-custom)
- **Delivered**: Full DEX parsing with annotation, debug info, and multi-DEX support

### Milestone 4: Java Runtime / Class Library -- ACHIEVED
- Object model: heap objects with class pointers and fields
- 450+ framework classes spanning Android, Java stdlib, Kotlin, and third-party libraries
- String (35+ methods), HashMap, ArrayList, Collections, Arrays, Objects
- Autoboxing for all primitive wrapper types
- Real ArrayList Iterator with for-each loop support
- Collection interfaces (Iterable/Collection/List/Set/Map) on 15+ classes
- Exception model with cross-method unwinding and finally blocks
- ByteBuffer, WeakReference/SoftReference, Enum, Number, Pair
- java.util.concurrent: AtomicInteger/Boolean/Reference, ConcurrentHashMap, LinkedBlockingQueue, etc.
- **Delivered**: Production-grade class library

### Milestone 5: Bytecode Interpreter -- ACHIEVED
- All 256 Dalvik opcodes with edge case handling
- Computed goto dispatch (256-entry table) for performance
- 64-frame pool, FNV-1a class hash table (O(1) lookup)
- Exception try/catch/finally with cross-method unwinding
- Varargs method invocation (pack_varargs)
- Null-safe instance-of/check-cast
- invoke-custom: Real LambdaMetafactory + StringConcatFactory
- invoke-polymorphic: MethodHandle.invoke/invokeExact with all 9 handle kinds
- const-method-handle / const-method-type: real DxMethodHandle/DxDexProtoId wrapping
- Inline caching for invoke-virtual (4-entry polymorphic IC, FIFO eviction)
- Method inlining for trivial getters/setters (bypass frame creation)
- Register file pinning for interpreter hot path
- Interface method table (itable) for O(1) interface dispatch with default methods
- Incremental GC with mark stack (256 objects/step batched phases)
- Custom ClassLoader support (PathClassLoader, DexClassLoader, URLClassLoader)
- Volatile field semantics (ACC_VOLATILE + __sync_synchronize barriers)
- Bytecode verifier: structural verification (boundaries, registers, indices, branches, payloads)
- **Delivered**: Full interpreter with production-grade opcode coverage, optimization, and verification

### Milestone 6: Android UI Rendering -- ACHIEVED
- Layout XML parsing (binary XML)
- 30+ view types: TextView, Button, EditText, ImageView, RecyclerView, ListView, GridView, Spinner, SeekBar, RatingBar, RadioButton/Group, FAB, TabLayout, ViewPager, WebView, Chip, BottomNav, SwipeRefreshLayout
- ConstraintLayout solver with guidelines, chains (spread/spread_inside/packed), bias
- Drawable loading: PNG/JPEG, vector (AXML->SVG->Canvas), 9-patch, StateListDrawable, LayerDrawable, ShapeDrawable
- Measure/layout pass: dx_ui_measure() with match_parent/wrap_content/fixed dp resolution
- Diff-based UI updates with dirty flags, version tracking, 60fps throttle
- Lazy child rendering (LazyVStack/LazyHStack for 20+ children)
- Focus management (focusable/focused state, auto-focus on EditText)
- Property animation support (alpha, rotation, scaleX/scaleY, translationX/translationY)
- WebView mapped to WKWebView bridge
- **Delivered**: Rich UI rendering with 30+ view types, constraint solving, and production-grade rendering pipeline

### Milestone 7: Activity Lifecycle & Navigation -- ACHIEVED
- Full lifecycle: onCreate->onPostCreate->onStart->onResume->onPostResume + teardown
- State save/restore: onSaveInstanceState/onRestoreInstanceState, Activity.recreate()
- Multi-activity navigation with Intent extras
- 16-deep back-stack; startActivityForResult/setResult/finish/onActivityResult
- Fragment lifecycle: onCreateView->onViewCreated->onStart->onResume
- Configuration class with orientation, screen dimensions, locale, density
- **Delivered**: Complete activity lifecycle and navigation

### Milestone 8: Event Handling & Touch -- ACHIEVED
- onClick on all view types, long-press support
- SwipeRefreshLayout pull-to-refresh
- MotionEvent dispatch
- Menu system: Menu/MenuItem/SubMenu/MenuInflater
- TextWatcher/Editable, CompoundButton isChecked/setChecked/toggle
- Back button: dx_runtime_dispatch_back calls Activity.onBackPressed
- **Delivered**: Full event handling including touch, menus, and text input

### Milestone 9: System Services & I/O -- ACHIEVED
- AssetManager.open() extracts from APK; InputStream with real read/available/close
- File I/O: File.createTempFile, Context.openFileInput/openFileOutput
- Filesystem: getExternalFilesDir, Environment paths
- Permissions: checkSelfPermission (safe vs dangerous), requestPermissions with callback
- SQLiteDatabase with insert/update/delete/rawQuery, ContentValues, Cursor, Room annotations
- BroadcastReceiver: registerReceiver/sendBroadcast with Intent action dispatch
- Service lifecycle: startService->onCreate->onStartCommand; IntentService subclass
- ContentProvider/ContentResolver stub CRUD
- **Delivered**: File I/O, assets, permissions, and system service stubs

### Milestone 10: Advanced Runtime -- ACHIEVED
- Reflection: Class.forName, Method.invoke, Field.get/set, getAnnotation
- Advanced reflection: Proxy.newProxyInstance, Array.newInstance, Constructor, getDeclaredMethods/Fields
- JNI bridge: Complete JNIEnv (232 functions), Call*Method, Get/Set*Field, RegisterNatives
- Cooperative threading: Thread.start (synchronous), ExecutorService, Future, CompletableFuture
- LiveData/ViewModel with observer notification
- Third-party libraries: RxJava3 (11 classes, 85 methods), OkHttp3 (18 classes, 120 methods), Retrofit2 (12 classes, 50 methods), Glide (6 classes, 40 methods)
- **Delivered**: Reflection, JNI, threading, and major third-party library support

### Milestone 11: Debug & Diagnostics -- ACHIEVED
- UI tree inspector (visual hierarchy debugging)
- Heap inspector (memory/object analysis)
- Error diagnostics (enhanced error reporting)
- Build/VERSION constants: SDK_INT=33, RELEASE="13"
- Line number tables from DEX debug_info_item
- Debug tracing: bytecode trace, class load trace, method call trace (per-method prefix filter)
- In-app inspectors: DEX browser (searchable classes/methods/fields), manifest inspector, resource inspector
- Profiling: method timing, opcode histogram, hot method ID, GC pause, allocation tracking
- Crash report generation with ShareSheet export
- Fuzzing harness (dx_fuzz_apk/dex/axml/resources, libFuzzer-compatible)
- ASan CI job for memory sanitization
- **Delivered**: Comprehensive debug, profiling, and security testing tooling

### Milestone 12: Networking -- ACHIEVED
- java.net.HttpURLConnection: Real URLSession bridge for GET/POST/PUT/DELETE
- Request headers, response headers, real response code + body as InputStream
- javax.net.ssl.HttpsURLConnection extends HttpURLConnection + SSL stubs
- OkHttp3: Request.Builder, Call.execute/enqueue, Response via real URLSession callback
- TCP Sockets: java.net.Socket/ServerSocket with real POSIX TCP (getaddrinfo/connect/accept)
- Retrofit2: Annotation-driven dispatch with real HTTP via OkHttp + URLSession
- **Delivered**: Real networking via iOS URLSession bridge + POSIX TCP sockets

## Test Coverage

- **147 tests** (26 suites) covering parser hardening, DEX parsing, VM execution, framework classes, UI rendering, and integration scenarios
- Swift Testing framework with DexLoomTests target
- GitHub Actions CI with iPhone + iPad simulator matrix
- ASan CI job for memory sanitization

## Current Feature Summary (~84% of To-Do complete)

### Fully Supported
- All 256 Dalvik opcodes with edge case handling (computed goto dispatch)
- invoke-custom: Real LambdaMetafactory + StringConcatFactory
- invoke-polymorphic: MethodHandle.invoke/invokeExact with all 9 handle kinds
- const-method-handle / const-method-type: real values
- Bytecode verifier: structural verification pass
- 450+ framework classes (Android, Java, Kotlin, RxJava, OkHttp, Retrofit, Glide)
- 30+ view types with ConstraintLayout solver (guidelines, chains, bias)
- Measure/layout pass with match_parent/wrap_content resolution
- Diff-based UI updates with 60fps throttle and lazy child rendering
- Full activity lifecycle with state save/restore and 16-deep task/back stack
- Fragment lifecycle, Service, BroadcastReceiver, ContentProvider
- Reflection including Proxy, Constructor, annotations
- JNI bridge (232 functions)
- AssetManager, File I/O, permissions system, file system sandboxing
- Touch events, menus, text input, long-press, focus management
- Cooperative threading, LiveData/ViewModel, Kotlin coroutines
- Real networking via URLSession (HttpURLConnection, OkHttp3, Retrofit2)
- TCP Sockets (java.net.Socket/ServerSocket with real POSIX networking)
- Incremental GC with mark stack (256 objects/step batched phases)
- Inline caching, method inlining, register file pinning
- Interface method table (itable) for O(1) interface dispatch
- Custom ClassLoader support, volatile field semantics
- Property animation (alpha, rotation, scale, translation)
- All drawable types: PNG/JPEG, vector, 9-patch, StateListDrawable, LayerDrawable, ShapeDrawable
- Debug tracing (bytecode, class load, method call), profiling infrastructure
- In-app inspectors: DEX browser, manifest inspector, resource inspector, UI tree, heap
- APK hardening: ZIP bomb, CRC32, path traversal, encrypted, ZIP64, mmap, signatures, split APK
- DEX hardening: Adler32, SHA-1, map parsing, hidden API detection
- Resource cache with 512-entry FIFO eviction
- Namespace-aware AXML attribute resolution
- Fuzzing harness (libFuzzer-compatible) + ASan CI

### Known Limitations
- Compose apps: fundamentally unsupported (need Compose compiler runtime)
- JNI: Can't load .so files (no dlopen); provides env for DEX-side JNI calls only
- Threading: cooperative (synchronous) only, no true concurrency
- Multidex: supported (up to 8 DEX files)
- App Bundle (.aab): not supported (split APK is supported)
- Obfuscated/heavily optimized APKs: may have issues

## Future Work
- Generational GC (young/old generations)
- Register type tracking in verifier
- App Bundle (.aab) support
- Core Graphics bridge for Canvas draw commands
- AVAudioPlayer bridge for MediaPlayer
- Opcode combination optimization (const/4 + if-eqz patterns)
- NaN-boxing for DxValue size reduction
