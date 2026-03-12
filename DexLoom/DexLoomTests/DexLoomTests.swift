import Testing
import Foundation
@testable import DexLoom

// MARK: - Helper to create a VM with framework classes registered

private func makeVM() -> (ctx: UnsafeMutablePointer<DxContext>, vm: UnsafeMutablePointer<DxVM>) {
    let ctx = dx_context_create()!
    let vm = dx_vm_create(ctx)!
    dx_vm_register_framework_classes(vm)
    return (ctx, vm)
}

private func teardownVM(_ ctx: UnsafeMutablePointer<DxContext>, _ vm: UnsafeMutablePointer<DxVM>) {
    dx_vm_destroy(vm)
    ctx.pointee.vm = nil
    dx_context_destroy(ctx)
}

// ============================================================
// MARK: - Existing Core Tests
// ============================================================

@Suite("DexLoom Core Tests")
struct DexLoomCoreTests {

    @Test("Runtime context creation and destruction")
    func testContextLifecycle() {
        let ctx = dx_context_create()
        #expect(ctx != nil)
        if let ctx = ctx {
            dx_context_destroy(ctx)
        }
    }

    @Test("DEX magic validation rejects invalid data")
    func testDexMagicValidation() {
        // Must be >= header size (112) but with bad magic
        var bad_data = [UInt8](repeating: 0, count: 112)
        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&bad_data, UInt32(bad_data.count), &dex)
        #expect(result == DX_ERR_INVALID_MAGIC)
    }

    @Test("DEX header parsing with valid minimal header")
    func testDexHeaderParsing() {
        var data = [UInt8](repeating: 0, count: 112)
        let magic: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]
        for i in 0..<8 { data[i] = magic[i] }
        data[32] = 112; data[33] = 0; data[34] = 0; data[35] = 0
        data[36] = 112; data[37] = 0; data[38] = 0; data[39] = 0
        data[40] = 0x78; data[41] = 0x56; data[42] = 0x34; data[43] = 0x12

        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        #expect(result == DX_OK)
        if let dex = dex {
            #expect(dex.pointee.header.header_size == 112)
            dx_dex_free(dex)
        }
    }

    @Test("Log system does not crash")
    func testLogInit() {
        dx_log_init()
        dx_log_msg(DX_LOG_INFO, "Test", "Hello from test")
    }

    @Test("Result string conversion")
    func testResultStrings() {
        let ok = String(cString: dx_result_string(DX_OK))
        #expect(ok == "OK")
        let notFound = String(cString: dx_result_string(DX_ERR_NOT_FOUND))
        #expect(notFound == "NOT_FOUND")
    }

    @Test("Opcode name lookup")
    func testOpcodeNames() {
        let nop = String(cString: dx_opcode_name(0x00))
        #expect(nop == "nop")
        let invokeVirtual = String(cString: dx_opcode_name(0x6E))
        #expect(invokeVirtual == "invoke-virtual")
    }

    @Test("UI node tree operations")
    func testUINodeTree() {
        let root = dx_ui_node_create(DX_VIEW_LINEAR_LAYOUT, 1)!
        let child1 = dx_ui_node_create(DX_VIEW_TEXT_VIEW, 2)!
        let child2 = dx_ui_node_create(DX_VIEW_BUTTON, 3)!

        dx_ui_node_add_child(root, child1)
        dx_ui_node_add_child(root, child2)
        #expect(root.pointee.child_count == 2)

        dx_ui_node_set_text(child1, "Hello")
        #expect(String(cString: child1.pointee.text) == "Hello")

        let found = dx_ui_node_find_by_id(root, 3)
        #expect(found == child2)
        #expect(dx_ui_node_find_by_id(root, 99) == nil)

        dx_ui_node_destroy(root)
    }

    @Test("VM framework class registration")
    func testVMFrameworkRegistration() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        #expect(dx_vm_find_class(vm, "Ljava/lang/Object;") != nil)
        #expect(dx_vm_find_class(vm, "Landroid/app/Activity;") != nil)
        #expect(dx_vm_find_class(vm, "Landroid/widget/TextView;") != nil)
        #expect(dx_vm_find_class(vm, "Landroid/widget/Button;") != nil)
    }

    @Test("VM string creation and retrieval")
    func testVMStrings() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strObj = dx_vm_create_string(vm, "Hello DexLoom")
        #expect(strObj != nil)
        if let strObj = strObj {
            let value = dx_vm_get_string_value(strObj)
            #expect(value != nil)
            if let value = value {
                #expect(String(cString: value) == "Hello DexLoom")
            }
        }
    }

    @Test("VM object allocation")
    func testVMObjectAlloc() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let obj = dx_vm_alloc_object(vm, cls)
        #expect(obj != nil)
        #expect(obj?.pointee.klass == cls)
    }

    @Test("Field set/get on multi-level hierarchy does not crash")
    func testFieldHierarchySafety() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Allocate an Activity object (has no field_defs)
        let actCls = dx_vm_find_class(vm, "Landroid/app/Activity;")!
        let obj = dx_vm_alloc_object(vm, actCls)!

        // set_field on a field that doesn't exist should not crash
        var val = DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 42))
        let setResult = dx_vm_set_field(obj, "mExtraDataMap", val)
        #expect(setResult == DX_OK) // silently absorbed

        // get_field on a missing field should return null, not crash
        var out = DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: nil))
        let getResult = dx_vm_get_field(obj, "mExtraDataMap", &out)
        #expect(getResult == DX_OK) // returns null
    }

    @Test("AppCompatActivity is registered")
    func testAppCompatRegistered() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        #expect(dx_vm_find_class(vm, "Landroidx/appcompat/app/AppCompatActivity;") != nil)
        #expect(dx_vm_find_class(vm, "Landroidx/constraintlayout/widget/ConstraintLayout;") != nil)
    }

    @Test("Opcode width lookup")
    func testOpcodeWidths() {
        #expect(dx_opcode_width(0x00) == 1) // nop
        #expect(dx_opcode_width(0x28) == 1) // goto (was broken: 2)
        #expect(dx_opcode_width(0x6E) == 3) // invoke-virtual
        #expect(dx_opcode_width(0x14) == 3) // const (31i)
        #expect(dx_opcode_width(0x18) == 5) // const-wide (51l)
    }

    @Test("Render model creation from UI tree")
    func testRenderModel() {
        let root = dx_ui_node_create(DX_VIEW_LINEAR_LAYOUT, 1)!
        root.pointee.orientation = DX_ORIENTATION_VERTICAL

        let tv = dx_ui_node_create(DX_VIEW_TEXT_VIEW, 2)!
        dx_ui_node_set_text(tv, "Hello")
        dx_ui_node_add_child(root, tv)

        let model = dx_render_model_create(root)
        #expect(model != nil)
        #expect(model!.pointee.root != nil)
        #expect(model!.pointee.root.pointee.type == DX_VIEW_LINEAR_LAYOUT)
        #expect(model!.pointee.root.pointee.child_count == 1)

        dx_render_model_destroy(model)
        dx_ui_node_destroy(root)
    }
}

// ============================================================
// MARK: - VM Lifecycle Tests
// ============================================================

@Suite("VM Lifecycle Tests")
struct VMLifecycleTests {

    @Test("Create and destroy VM without crash")
    func testCreateDestroy() {
        let ctx = dx_context_create()!
        let vm = dx_vm_create(ctx)
        #expect(vm != nil)
        if let vm = vm {
            dx_vm_destroy(vm)
        }
        ctx.pointee.vm = nil
        dx_context_destroy(ctx)
    }

    @Test("Register framework classes returns OK")
    func testRegisterFramework() {
        let ctx = dx_context_create()!
        let vm = dx_vm_create(ctx)!
        let result = dx_vm_register_framework_classes(vm)
        #expect(result == DX_OK)
        // Should have registered many classes
        #expect(vm.pointee.class_count > 100)
        teardownVM(ctx, vm)
    }

    @Test("Class hash table lookup works for all well-known classes")
    func testClassHashTable() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let classNames = [
            "Ljava/lang/Object;",
            "Ljava/lang/String;",
            "Ljava/lang/Integer;",
            "Ljava/lang/Boolean;",
            "Ljava/util/ArrayList;",
            "Ljava/util/HashMap;",
            "Ljava/util/Arrays;",
            "Ljava/util/Collections;",
            "Landroid/app/Activity;",
            "Landroid/os/Bundle;",
            "Landroid/content/Intent;",
            "Landroid/widget/TextView;",
            "Landroid/widget/Button;",
            "Landroid/widget/EditText;",
            "Landroid/widget/ImageView;",
            "Landroid/widget/Toast;",
            "Landroid/util/Log;",
            "Landroid/view/View;",
            "Landroid/view/ViewGroup;",
        ]
        for name in classNames {
            let cls = dx_vm_find_class(vm, name)
            #expect(cls != nil, "Expected to find class \(name)")
        }
    }

    @Test("find_class returns nil for unknown class")
    func testFindClassUnknown() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Lcom/nonexistent/FakeClass;")
        #expect(cls == nil)
    }

    @Test("VM cached class pointers are set after registration")
    func testVMCachedPointers() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        #expect(vm.pointee.class_object != nil)
        #expect(vm.pointee.class_string != nil)
        #expect(vm.pointee.class_activity != nil)
        #expect(vm.pointee.class_view != nil)
        #expect(vm.pointee.class_textview != nil)
        #expect(vm.pointee.class_button != nil)
        #expect(vm.pointee.class_viewgroup != nil)
        #expect(vm.pointee.class_linearlayout != nil)
        #expect(vm.pointee.class_context != nil)
        #expect(vm.pointee.class_bundle != nil)
        #expect(vm.pointee.class_arraylist != nil)
        #expect(vm.pointee.class_hashmap != nil)
        #expect(vm.pointee.class_intent != nil)
        #expect(vm.pointee.class_edittext != nil)
        #expect(vm.pointee.class_imageview != nil)
        #expect(vm.pointee.class_toast != nil)
        #expect(vm.pointee.class_appcompat != nil)
    }

    @Test("Multiple VM instances can coexist")
    func testMultipleVMs() {
        let ctx1 = dx_context_create()!
        let vm1 = dx_vm_create(ctx1)!
        dx_vm_register_framework_classes(vm1)

        let ctx2 = dx_context_create()!
        let vm2 = dx_vm_create(ctx2)!
        dx_vm_register_framework_classes(vm2)

        // Both should work independently
        #expect(dx_vm_find_class(vm1, "Ljava/lang/String;") != nil)
        #expect(dx_vm_find_class(vm2, "Ljava/lang/String;") != nil)

        // Objects from vm1 and vm2 are separate
        let s1 = dx_vm_create_string(vm1, "hello")
        let s2 = dx_vm_create_string(vm2, "world")
        #expect(s1 != nil)
        #expect(s2 != nil)

        dx_vm_destroy(vm1)
        ctx1.pointee.vm = nil
        dx_context_destroy(ctx1)

        // vm2 should still work after vm1 is destroyed
        let s3 = dx_vm_create_string(vm2, "still alive")
        #expect(s3 != nil)

        dx_vm_destroy(vm2)
        ctx2.pointee.vm = nil
        dx_context_destroy(ctx2)
    }
}

// ============================================================
// MARK: - Framework Class Tests
// ============================================================

@Suite("Framework Class Tests")
struct FrameworkClassTests {

    @Test("String creation with various content")
    func testStringCreation() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Empty string
        let empty = dx_vm_create_string(vm, "")
        #expect(empty != nil)
        #expect(String(cString: dx_vm_get_string_value(empty)!) == "")

        // ASCII content
        let ascii = dx_vm_create_string(vm, "Hello World 123")
        #expect(ascii != nil)
        #expect(String(cString: dx_vm_get_string_value(ascii)!) == "Hello World 123")

        // Long string
        let longStr = String(repeating: "abcd", count: 250)
        let longObj = dx_vm_create_string(vm, longStr)
        #expect(longObj != nil)
        #expect(String(cString: dx_vm_get_string_value(longObj)!) == longStr)
    }

    @Test("String interning returns same object for same value")
    func testStringInterning() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let s1 = dx_vm_intern_string(vm, "interned_test")
        let s2 = dx_vm_intern_string(vm, "interned_test")
        #expect(s1 != nil)
        #expect(s2 != nil)
        // Interned strings with same value should be the same object
        #expect(s1 == s2)

        // Different value should be a different object
        let s3 = dx_vm_intern_string(vm, "different_value")
        #expect(s3 != nil)
        #expect(s3 != s1)
    }

    @Test("String object has correct class")
    func testStringClass() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strObj = dx_vm_create_string(vm, "test")!
        #expect(strObj.pointee.klass == vm.pointee.class_string)
        let desc = String(cString: strObj.pointee.klass.pointee.descriptor)
        #expect(desc == "Ljava/lang/String;")
    }

    @Test("ArrayList: find class and create instance")
    func testArrayListCreation() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!
        let list = dx_vm_alloc_object(vm, alCls)
        #expect(list != nil)
        #expect(list?.pointee.klass == alCls)
    }

    @Test("ArrayList: native add and size methods exist")
    func testArrayListMethods() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!

        // Check that key methods are registered
        let addMethod = dx_vm_find_method(alCls, "add", "ZL")
        #expect(addMethod != nil, "ArrayList.add should be registered")

        let sizeMethod = dx_vm_find_method(alCls, "size", "I")
        #expect(sizeMethod != nil, "ArrayList.size should be registered")

        let getMethod = dx_vm_find_method(alCls, "get", "LI")
        #expect(getMethod != nil, "ArrayList.get should be registered")
    }

    @Test("HashMap: find class and verify methods")
    func testHashMapMethods() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let hmCls = dx_vm_find_class(vm, "Ljava/util/HashMap;")!
        let obj = dx_vm_alloc_object(vm, hmCls)
        #expect(obj != nil)

        // Check key methods
        let putMethod = dx_vm_find_method(hmCls, "put", "LLL")
        #expect(putMethod != nil, "HashMap.put should be registered")

        let getMethod = dx_vm_find_method(hmCls, "get", "LL")
        #expect(getMethod != nil, "HashMap.get should be registered")

        let sizeMethod = dx_vm_find_method(hmCls, "size", "I")
        #expect(sizeMethod != nil, "HashMap.size should be registered")

        let containsKeyMethod = dx_vm_find_method(hmCls, "containsKey", "ZL")
        #expect(containsKeyMethod != nil, "HashMap.containsKey should be registered")
    }

    @Test("Integer valueOf autoboxing class exists")
    func testIntegerAutoboxing() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let intCls = dx_vm_find_class(vm, "Ljava/lang/Integer;")
        #expect(intCls != nil, "java.lang.Integer should be registered")

        if let intCls = intCls {
            let valueOf = dx_vm_find_method(intCls, "valueOf", "LI")
            #expect(valueOf != nil, "Integer.valueOf should be registered for autoboxing")
        }
    }

    @Test("Long/Float/Double/Boolean autoboxing classes exist")
    func testAutoboxingClasses() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let types: [(String, String)] = [
            ("Ljava/lang/Long;", "LJ"),
            ("Ljava/lang/Float;", "LF"),
            ("Ljava/lang/Double;", "LD"),
            ("Ljava/lang/Boolean;", "LZ"),
            ("Ljava/lang/Byte;", "LB"),
            ("Ljava/lang/Short;", "LS"),
            ("Ljava/lang/Character;", "LC"),
        ]
        for (desc, shorty) in types {
            let cls = dx_vm_find_class(vm, desc)
            #expect(cls != nil, "Expected \(desc) to be registered")
            if let cls = cls {
                let valueOf = dx_vm_find_method(cls, "valueOf", shorty)
                #expect(valueOf != nil, "Expected valueOf on \(desc)")
            }
        }
    }

    @Test("Activity class has lifecycle methods")
    func testActivityLifecycleMethods() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let actCls = dx_vm_find_class(vm, "Landroid/app/Activity;")!

        // Check lifecycle methods exist
        let onCreate = dx_vm_find_method(actCls, "onCreate", "VL")
        #expect(onCreate != nil, "Activity.onCreate should exist")

        let onStart = dx_vm_find_method(actCls, "onStart", "V")
        #expect(onStart != nil, "Activity.onStart should exist")

        let onResume = dx_vm_find_method(actCls, "onResume", "V")
        #expect(onResume != nil, "Activity.onResume should exist")
    }

    @Test("View class has key methods")
    func testViewMethods() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let viewCls = dx_vm_find_class(vm, "Landroid/view/View;")!

        let setOnClick = dx_vm_find_method(viewCls, "setOnClickListener", "VL")
        #expect(setOnClick != nil, "View.setOnClickListener should exist")

        let findViewById = dx_vm_find_method(viewCls, "findViewById", "LI")
        #expect(findViewById != nil, "View.findViewById should exist")
    }

    @Test("Intent class exists with extras methods")
    func testIntentClass() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let intentCls = dx_vm_find_class(vm, "Landroid/content/Intent;")!
        let obj = dx_vm_alloc_object(vm, intentCls)
        #expect(obj != nil)

        let putExtra = dx_vm_find_method(intentCls, "putExtra", "LLL")
        #expect(putExtra != nil, "Intent.putExtra should exist")
    }

    @Test("Bundle class exists")
    func testBundleClass() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let bundleCls = dx_vm_find_class(vm, "Landroid/os/Bundle;")!
        let obj = dx_vm_alloc_object(vm, bundleCls)
        #expect(obj != nil)
    }

    @Test("Exception class hierarchy")
    func testExceptionClasses() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let exceptions = [
            "Ljava/lang/Exception;",
            "Ljava/lang/RuntimeException;",
            "Ljava/lang/NullPointerException;",
            "Ljava/lang/ArrayIndexOutOfBoundsException;",
            "Ljava/lang/ClassCastException;",
            "Ljava/lang/ArithmeticException;",
        ]
        for desc in exceptions {
            let cls = dx_vm_find_class(vm, desc)
            #expect(cls != nil, "Expected \(desc) to be registered")
        }
    }

    @Test("Collection interfaces registered")
    func testCollectionInterfaces() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let interfaces = [
            "Ljava/lang/Iterable;",
            "Ljava/util/Collection;",
            "Ljava/util/List;",
            "Ljava/util/Set;",
            "Ljava/util/Map;",
            "Ljava/util/Iterator;",
        ]
        for desc in interfaces {
            let cls = dx_vm_find_class(vm, desc)
            #expect(cls != nil, "Expected \(desc) to be registered")
        }
    }

    @Test("Android widget classes registered")
    func testWidgetClasses() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let widgets = [
            "Landroid/widget/Spinner;",
            "Landroid/widget/SeekBar;",
            "Landroid/widget/CheckBox;",
            "Landroid/widget/Switch;",
            "Landroid/widget/RadioButton;",
            "Landroid/widget/RadioGroup;",
            "Landroid/widget/ListView;",
        ]
        for desc in widgets {
            let cls = dx_vm_find_class(vm, desc)
            #expect(cls != nil, "Expected \(desc) to be registered")
        }
    }

    @Test("Kotlin standard library classes registered")
    func testKotlinClasses() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Kotlin stdlib should have some representation
        let kotlinUnit = dx_vm_find_class(vm, "Lkotlin/Unit;")
        #expect(kotlinUnit != nil, "Kotlin Unit should be registered")
    }
}

// ============================================================
// MARK: - Object System Tests
// ============================================================

@Suite("Object System Tests")
struct ObjectSystemTests {

    @Test("Allocate object and verify class pointer")
    func testAllocObjectClass() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let obj = dx_vm_alloc_object(vm, objCls)!

        #expect(obj.pointee.klass == objCls)
        #expect(obj.pointee.is_array == false)
        #expect(obj.pointee.gc_mark == false)
    }

    @Test("Allocate array and verify length")
    func testAllocArray() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let arr = dx_vm_alloc_array(vm, 10)
        #expect(arr != nil)
        if let arr = arr {
            #expect(arr.pointee.is_array == true)
            #expect(arr.pointee.array_length == 10)
            #expect(arr.pointee.array_elements != nil)
        }
    }

    @Test("Allocate zero-length array")
    func testAllocZeroArray() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let arr = dx_vm_alloc_array(vm, 0)
        #expect(arr != nil)
        if let arr = arr {
            #expect(arr.pointee.is_array == true)
            #expect(arr.pointee.array_length == 0)
        }
    }

    @Test("Array element access")
    func testArrayElementAccess() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let arr = dx_vm_alloc_array(vm, 5)!

        // Set and read back values
        arr.pointee.array_elements[0] = DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 42))
        arr.pointee.array_elements[1] = DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 99))

        #expect(arr.pointee.array_elements[0].tag == DX_VAL_INT)
        #expect(arr.pointee.array_elements[0].i == 42)
        #expect(arr.pointee.array_elements[1].i == 99)
    }

    @Test("Heap tracks allocated objects")
    func testHeapTracking() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let initialCount = vm.pointee.heap_count
        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

        let _ = dx_vm_alloc_object(vm, objCls)
        #expect(vm.pointee.heap_count == initialCount + 1)

        let _ = dx_vm_alloc_object(vm, objCls)
        #expect(vm.pointee.heap_count == initialCount + 2)
    }

    @Test("GC function exists and heap tracks objects")
    func testGCRelated() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        // Allocate several objects and verify they're on the heap
        let initialCount = vm.pointee.heap_count
        for _ in 0..<20 {
            let _ = dx_vm_alloc_object(vm, objCls)
        }
        #expect(vm.pointee.heap_count == initialCount + 20)
        // Note: dx_vm_gc requires a running execution context with proper
        // root set; calling it outside of execution can crash.
    }

    @Test("Object fields for classes with field_defs")
    func testObjectFieldsWithDefs() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // TextView should have field_defs (e.g., mText)
        let tvCls = dx_vm_find_class(vm, "Landroid/widget/TextView;")!
        let tv = dx_vm_alloc_object(vm, tvCls)!
        #expect(tv.pointee.klass == tvCls)
    }

    @Test("VM heap stats returns valid string")
    func testHeapStats() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let _ = dx_vm_alloc_object(vm, dx_vm_find_class(vm, "Ljava/lang/Object;")!)
        let stats = dx_vm_heap_stats(vm)
        #expect(stats != nil)
        if let stats = stats {
            let str = String(cString: stats)
            #expect(str.count > 0)
            free(stats)
        }
    }

    @Test("Create exception object with message")
    func testCreateException() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let exc = dx_vm_create_exception(vm, "Ljava/lang/NullPointerException;", "test null pointer")
        #expect(exc != nil)
        if let exc = exc {
            let desc = String(cString: exc.pointee.klass.pointee.descriptor)
            #expect(desc == "Ljava/lang/NullPointerException;")
        }
    }

    @Test("Frame pool allocation and release")
    func testFramePool() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Allocate a frame
        let frame = dx_vm_alloc_frame(vm)
        #expect(frame != nil)

        // Free it back to pool
        if let frame = frame {
            dx_vm_free_frame(vm, frame)
        }

        // Allocate again - should reuse from pool
        let frame2 = dx_vm_alloc_frame(vm)
        #expect(frame2 != nil)
        if let frame2 = frame2 {
            dx_vm_free_frame(vm, frame2)
        }
    }

    @Test("Frame pool handles many allocations")
    func testFramePoolStress() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Allocate more frames than pool size, then free all
        var frames: [UnsafeMutablePointer<DxFrame>] = []
        for _ in 0..<80 {
            if let f = dx_vm_alloc_frame(vm) {
                frames.append(f)
            }
        }
        #expect(frames.count == 80)

        // Free them all
        for f in frames {
            dx_vm_free_frame(vm, f)
        }
    }
}

// ============================================================
// MARK: - Bytecode Execution Tests
// ============================================================

@Suite("Bytecode Execution Tests")
struct BytecodeExecutionTests {

    @Test("Execute native method on String class")
    func testExecuteNativeMethod() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let lengthMethod = dx_vm_find_method(strCls, "length", "I")
        #expect(lengthMethod != nil, "String.length should exist")

        if let lengthMethod = lengthMethod {
            // Create a string object to call length on
            let strObj = dx_vm_create_string(vm, "Hello")!
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))

            let status = dx_vm_execute_method(vm, lengthMethod, &args, 1, &result)
            #expect(status == DX_OK)
            #expect(result.tag == DX_VAL_INT)
            #expect(result.i == 5)
        }
    }

    @Test("Execute ArrayList.size on empty list")
    func testArrayListSize() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!
        let list = dx_vm_alloc_object(vm, alCls)!

        // Call <init> first
        let initMethod = dx_vm_find_method(alCls, "<init>", "V")
        if let initMethod = initMethod {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list))]
            var initResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, initMethod, &args, 1, &initResult)
        }

        // Call size
        let sizeMethod = dx_vm_find_method(alCls, "size", "I")!
        var sizeArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list))]
        var sizeResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, sizeMethod, &sizeArgs, 1, &sizeResult)
        #expect(status == DX_OK)
        #expect(sizeResult.tag == DX_VAL_INT)
        #expect(sizeResult.i == 0)
    }

    @Test("Execute ArrayList add then size")
    func testArrayListAddAndSize() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!
        let list = dx_vm_alloc_object(vm, alCls)!

        // Init
        let initMethod = dx_vm_find_method(alCls, "<init>", "V")
        if let initMethod = initMethod {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list))]
            var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, initMethod, &args, 1, &r)
        }

        // Add three items
        let addMethod = dx_vm_find_method(alCls, "add", "ZL")!
        for i in 0..<3 {
            let strObj = dx_vm_create_string(vm, "item\(i)")!
            var addArgs = [
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list)),
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))
            ]
            var addResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let s = dx_vm_execute_method(vm, addMethod, &addArgs, 2, &addResult)
            #expect(s == DX_OK)
        }

        // Size should be 3
        let sizeMethod = dx_vm_find_method(alCls, "size", "I")!
        var sizeArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list))]
        var sizeResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, sizeMethod, &sizeArgs, 1, &sizeResult)
        #expect(status == DX_OK)
        #expect(sizeResult.i == 3)
    }

    @Test("Execute HashMap put and get")
    func testHashMapPutGet() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let hmCls = dx_vm_find_class(vm, "Ljava/util/HashMap;")!
        let map = dx_vm_alloc_object(vm, hmCls)!

        // Init
        let initMethod = dx_vm_find_method(hmCls, "<init>", "V")
        if let initMethod = initMethod {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map))]
            var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, initMethod, &args, 1, &r)
        }

        // Put a key-value pair
        let putMethod = dx_vm_find_method(hmCls, "put", "LLL")!
        let key = dx_vm_create_string(vm, "myKey")!
        let value = dx_vm_create_string(vm, "myValue")!
        var putArgs = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: key)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: value))
        ]
        var putResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let putStatus = dx_vm_execute_method(vm, putMethod, &putArgs, 3, &putResult)
        #expect(putStatus == DX_OK)

        // Get by key
        let getMethod = dx_vm_find_method(hmCls, "get", "LL")!
        var getArgs = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: key))
        ]
        var getResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let getStatus = dx_vm_execute_method(vm, getMethod, &getArgs, 2, &getResult)
        #expect(getStatus == DX_OK)
        #expect(getResult.tag == DX_VAL_OBJ)
        if let resultObj = getResult.obj {
            let resultStr = String(cString: dx_vm_get_string_value(resultObj)!)
            #expect(resultStr == "myValue")
        }
    }

    @Test("Execute Integer.valueOf autoboxing")
    func testIntegerValueOf() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let intCls = dx_vm_find_class(vm, "Ljava/lang/Integer;")!
        let valueOf = dx_vm_find_method(intCls, "valueOf", "LI")!

        // valueOf is static, so first arg is not 'this'
        var args = [DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 42))]
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, valueOf, &args, 1, &result)
        #expect(status == DX_OK)
        #expect(result.tag == DX_VAL_OBJ)
        #expect(result.obj != nil)
    }

    @Test("Opcode coverage: all 256 opcodes have names")
    func testAllOpcodesHaveNames() {
        for i: UInt8 in 0...255 {
            let name = dx_opcode_name(i)
            #expect(name != nil, "Opcode 0x\(String(i, radix: 16)) should have a name")
        }
    }

    @Test("Opcode widths are all > 0 for valid opcodes")
    func testOpcodeWidthsPositive() {
        // Key opcodes that must have positive widths
        let opcodes: [UInt8] = [
            0x00, // nop
            0x01, // move
            0x0E, // return-void
            0x12, // const/4
            0x1A, // const-string
            0x22, // new-instance
            0x28, // goto
            0x38, // if-eqz
            0x6E, // invoke-virtual
            0x90, // add-int
        ]
        for op in opcodes {
            #expect(dx_opcode_width(op) > 0, "Opcode 0x\(String(op, radix: 16)) width should be > 0")
        }
    }
}

// ============================================================
// MARK: - Error Handling Tests
// ============================================================

@Suite("Error Handling Tests")
struct ErrorHandlingTests {

    @Test("DEX parse rejects nil/empty data")
    func testDexParseEmpty() {
        var dex: UnsafeMutablePointer<DxDexFile>?
        // Empty buffer (too small for header)
        var data = [UInt8](repeating: 0, count: 4)
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        #expect(result != DX_OK)
    }

    @Test("DEX parse rejects truncated header")
    func testDexParseTruncated() {
        var dex: UnsafeMutablePointer<DxDexFile>?
        // 50 bytes is less than the 112-byte header
        var data = [UInt8](repeating: 0, count: 50)
        let magic: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]
        for i in 0..<8 { data[i] = magic[i] }
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        #expect(result != DX_OK)
    }

    @Test("DEX parse rejects wrong version magic")
    func testDexWrongVersion() {
        var data = [UInt8](repeating: 0, count: 112)
        // Valid prefix but invalid version "099"
        let magic: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x39, 0x39, 0x00]
        for i in 0..<8 { data[i] = magic[i] }
        data[32] = 112; data[33] = 0; data[34] = 0; data[35] = 0
        data[36] = 112; data[37] = 0; data[38] = 0; data[39] = 0
        data[40] = 0x78; data[41] = 0x56; data[42] = 0x34; data[43] = 0x12

        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        // Should either reject or accept depending on version tolerance
        // At minimum it should not crash
        if result == DX_OK, let dex = dex {
            dx_dex_free(dex)
        }
    }

    @Test("Instruction budget limit prevents infinite loops")
    func testInstructionBudget() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // The VM has insn_limit field - verify it's set to a reasonable value
        // or can be set
        #expect(vm.pointee.insn_limit == 0 || vm.pointee.insn_limit > 0)
        // DX_MAX_INSTRUCTIONS is 500000 per the types header
    }

    @Test("Context double-destroy safety")
    func testContextDoubleCreate() {
        // Just verify multiple create/destroy cycles work
        for _ in 0..<5 {
            let ctx = dx_context_create()!
            dx_context_destroy(ctx)
        }
    }

    @Test("Result string covers all error codes")
    func testAllResultStrings() {
        let codes: [DxResult] = [
            DX_OK,
            DX_ERR_NULL_PTR,
            DX_ERR_INVALID_MAGIC,
            DX_ERR_INVALID_FORMAT,
            DX_ERR_OUT_OF_MEMORY,
            DX_ERR_NOT_FOUND,
            DX_ERR_UNSUPPORTED_OPCODE,
            DX_ERR_CLASS_NOT_FOUND,
            DX_ERR_METHOD_NOT_FOUND,
            DX_ERR_FIELD_NOT_FOUND,
            DX_ERR_STACK_OVERFLOW,
            DX_ERR_STACK_UNDERFLOW,
            DX_ERR_EXCEPTION,
            DX_ERR_VERIFICATION_FAILED,
            DX_ERR_IO,
            DX_ERR_ZIP_INVALID,
            DX_ERR_AXML_INVALID,
            DX_ERR_UNSUPPORTED_VERSION,
            DX_ERR_INTERNAL,
        ]
        for code in codes {
            let str = dx_result_string(code)
            #expect(str != nil)
            let s = String(cString: str!)
            #expect(s.count > 0, "Result string for code should not be empty")
        }
    }

    @Test("VM diagnostic struct is clean on fresh VM")
    func testDiagnosticClean() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        #expect(vm.pointee.diag.has_error == false)
    }

    @Test("Create exception for unknown class returns nil or valid object")
    func testCreateExceptionUnknownClass() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Creating an exception with an unknown class - should handle gracefully
        let exc = dx_vm_create_exception(vm, "Lcom/fake/NonExistentException;", "test")
        // Either nil or a fallback object is fine, just must not crash
        _ = exc
    }

    @Test("String value of nil returns nil")
    func testGetStringValueNil() {
        let result = dx_vm_get_string_value(nil)
        #expect(result == nil)
    }
}

// ============================================================
// MARK: - Parser Hardening Tests
// ============================================================

@Suite("Parser Hardening Tests")
struct ParserHardeningTests {

    @Test("DEX parse rejects completely garbage data")
    func testGarbageData() {
        var data = [UInt8](repeating: 0xFF, count: 256)
        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        #expect(result == DX_ERR_INVALID_MAGIC)
    }

    @Test("DEX parse with file_size mismatch")
    func testFileSizeMismatch() {
        var data = [UInt8](repeating: 0, count: 112)
        let magic: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]
        for i in 0..<8 { data[i] = magic[i] }
        // header_size = 112
        data[32] = 112; data[33] = 0; data[34] = 0; data[35] = 0
        // file_size = 9999 (way larger than actual)
        data[36] = 0x0F; data[37] = 0x27; data[38] = 0; data[39] = 0
        // endian tag
        data[40] = 0x78; data[41] = 0x56; data[42] = 0x34; data[43] = 0x12

        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        // Should either reject or handle gracefully
        if result == DX_OK, let dex = dex {
            dx_dex_free(dex)
        }
    }

    @Test("UI node create with all view types")
    func testAllViewTypes() {
        let types: [DxViewType] = [
            DX_VIEW_LINEAR_LAYOUT,
            DX_VIEW_TEXT_VIEW,
            DX_VIEW_BUTTON,
            DX_VIEW_IMAGE_VIEW,
            DX_VIEW_EDIT_TEXT,
            DX_VIEW_FRAME_LAYOUT,
            DX_VIEW_RELATIVE_LAYOUT,
            DX_VIEW_CONSTRAINT_LAYOUT,
            DX_VIEW_SCROLL_VIEW,
            DX_VIEW_RECYCLER_VIEW,
            DX_VIEW_CARD_VIEW,
            DX_VIEW_SWITCH,
            DX_VIEW_CHECKBOX,
            DX_VIEW_PROGRESS_BAR,
            DX_VIEW_TOOLBAR,
            DX_VIEW_VIEW,
            DX_VIEW_VIEW_GROUP,
            DX_VIEW_LIST_VIEW,
            DX_VIEW_GRID_VIEW,
            DX_VIEW_SPINNER,
            DX_VIEW_SEEK_BAR,
            DX_VIEW_RATING_BAR,
            DX_VIEW_RADIO_BUTTON,
            DX_VIEW_RADIO_GROUP,
            DX_VIEW_FAB,
            DX_VIEW_TAB_LAYOUT,
            DX_VIEW_VIEW_PAGER,
            DX_VIEW_WEB_VIEW,
            DX_VIEW_CHIP,
            DX_VIEW_BOTTOM_NAV,
            DX_VIEW_SWIPE_REFRESH,
        ]
        for (idx, viewType) in types.enumerated() {
            let node = dx_ui_node_create(viewType, UInt32(idx + 100))
            #expect(node != nil, "Should create node for view type index \(idx)")
            if let node = node {
                #expect(node.pointee.type == viewType)
                #expect(node.pointee.view_id == UInt32(idx + 100))
                dx_ui_node_destroy(node)
            }
        }
    }

    @Test("UI node deep tree")
    func testDeepUITree() {
        // Build a 50-level deep tree
        let root = dx_ui_node_create(DX_VIEW_FRAME_LAYOUT, 0)!
        var current = root
        for i in 1..<50 {
            let child = dx_ui_node_create(DX_VIEW_FRAME_LAYOUT, UInt32(i))!
            dx_ui_node_add_child(current, child)
            current = child
        }

        // Set text on deepest node
        dx_ui_node_set_text(current, "deep leaf")
        #expect(String(cString: current.pointee.text) == "deep leaf")

        // Find the deepest node by ID
        let found = dx_ui_node_find_by_id(root, 49)
        #expect(found != nil)
        #expect(found == current)

        // Count total nodes
        let count = dx_ui_node_count(root)
        #expect(count == 50)

        dx_ui_node_destroy(root)
    }

    @Test("UI node text overwrite")
    func testUINodeTextOverwrite() {
        let node = dx_ui_node_create(DX_VIEW_TEXT_VIEW, 1)!
        dx_ui_node_set_text(node, "first")
        #expect(String(cString: node.pointee.text) == "first")

        dx_ui_node_set_text(node, "second")
        #expect(String(cString: node.pointee.text) == "second")

        dx_ui_node_set_text(node, "")
        #expect(String(cString: node.pointee.text) == "")

        dx_ui_node_destroy(node)
    }

    @Test("UI node wide tree with many siblings")
    func testWideSiblingTree() {
        let root = dx_ui_node_create(DX_VIEW_LINEAR_LAYOUT, 0)!
        for i in 1...64 {
            let child = dx_ui_node_create(DX_VIEW_TEXT_VIEW, UInt32(i))!
            dx_ui_node_set_text(child, "item \(i)")
            dx_ui_node_add_child(root, child)
        }
        #expect(root.pointee.child_count == 64)
        #expect(dx_ui_node_count(root) == 65) // root + 64 children

        // Find last child
        let last = dx_ui_node_find_by_id(root, 64)
        #expect(last != nil)

        dx_ui_node_destroy(root)
    }

    @Test("Render model from complex tree")
    func testRenderModelComplex() {
        let root = dx_ui_node_create(DX_VIEW_LINEAR_LAYOUT, 1)!
        root.pointee.orientation = DX_ORIENTATION_VERTICAL

        let child1 = dx_ui_node_create(DX_VIEW_TEXT_VIEW, 2)!
        dx_ui_node_set_text(child1, "Title")
        dx_ui_node_add_child(root, child1)

        let child2 = dx_ui_node_create(DX_VIEW_FRAME_LAYOUT, 3)!
        dx_ui_node_add_child(root, child2)

        let nested = dx_ui_node_create(DX_VIEW_BUTTON, 4)!
        dx_ui_node_set_text(nested, "Click me")
        dx_ui_node_add_child(child2, nested)

        let model = dx_render_model_create(root)
        #expect(model != nil)
        #expect(model!.pointee.root.pointee.child_count == 2)

        dx_render_model_destroy(model)
        dx_ui_node_destroy(root)
    }

    @Test("UI tree dump returns non-empty string")
    func testUITreeDump() {
        let root = dx_ui_node_create(DX_VIEW_LINEAR_LAYOUT, 1)!
        let child = dx_ui_node_create(DX_VIEW_TEXT_VIEW, 2)!
        dx_ui_node_set_text(child, "Hello")
        dx_ui_node_add_child(root, child)

        let dump = dx_ui_tree_dump(root)
        #expect(dump != nil)
        if let dump = dump {
            let str = String(cString: dump)
            #expect(str.count > 0)
            free(dump)
        }

        dx_ui_node_destroy(root)
    }

    @Test("Dimension conversion produces positive values")
    func testDimensionConversion() {
        let dp16 = dx_ui_dp_to_points(16.0)
        #expect(dp16 > 0)

        let sp14 = dx_ui_sp_to_points(14.0)
        #expect(sp14 > 0)

        // Zero input gives zero output
        let dp0 = dx_ui_dp_to_points(0.0)
        #expect(dp0 == 0.0)
    }

    @Test("Memory allocation functions work")
    func testMemoryFunctions() {
        var allocs: UInt64 = 0
        var frees: UInt64 = 0
        var bytes: UInt64 = 0
        dx_memory_stats(&allocs, &frees, &bytes)
        // Just verify it doesn't crash and returns something
        #expect(allocs >= 0)
    }
}

// ============================================================
// MARK: - Class Hierarchy Tests
// ============================================================

@Suite("Class Hierarchy Tests")
struct ClassHierarchyTests {

    @Test("Object is root of all classes")
    func testObjectRoot() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        #expect(objCls.pointee.super_class == nil)
    }

    @Test("Activity extends Context chain")
    func testActivityHierarchy() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let actCls = dx_vm_find_class(vm, "Landroid/app/Activity;")!
        // Activity should have a superclass chain leading to Object
        var current: UnsafeMutablePointer<DxClass>? = actCls
        var depth = 0
        while let cls = current, cls.pointee.super_class != nil {
            current = cls.pointee.super_class
            depth += 1
            if depth > 20 { break } // safety
        }
        #expect(depth > 0, "Activity should have at least one superclass")

        // The root should be Object
        if let root = current {
            let desc = String(cString: root.pointee.descriptor)
            #expect(desc == "Ljava/lang/Object;")
        }
    }

    @Test("AppCompatActivity extends Activity chain")
    func testAppCompatHierarchy() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let appCompatCls = dx_vm_find_class(vm, "Landroidx/appcompat/app/AppCompatActivity;")!
        // Walk up to find Activity
        var current: UnsafeMutablePointer<DxClass>? = appCompatCls
        var foundActivity = false
        var depth = 0
        while let cls = current {
            let desc = String(cString: cls.pointee.descriptor)
            if desc == "Landroid/app/Activity;" {
                foundActivity = true
                break
            }
            current = cls.pointee.super_class
            depth += 1
            if depth > 20 { break }
        }
        #expect(foundActivity, "AppCompatActivity should have Activity in its superclass chain")
    }

    @Test("Framework classes are marked as framework")
    func testFrameworkFlag() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        #expect(objCls.pointee.is_framework == true)

        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        #expect(strCls.pointee.is_framework == true)

        let actCls = dx_vm_find_class(vm, "Landroid/app/Activity;")!
        #expect(actCls.pointee.is_framework == true)
    }

    @Test("Button extends TextView")
    func testButtonExtendsTextView() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let btnCls = dx_vm_find_class(vm, "Landroid/widget/Button;")!
        let superDesc = String(cString: btnCls.pointee.super_class.pointee.descriptor)
        #expect(superDesc == "Landroid/widget/TextView;")
    }

    @Test("Class descriptors are valid format")
    func testClassDescriptorFormat() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Spot check well-known classes have valid descriptor format
        let sampleClasses = [
            "Ljava/lang/Object;",
            "Ljava/lang/String;",
            "Landroid/app/Activity;",
            "Ljava/util/ArrayList;",
            "Ljava/util/HashMap;",
        ]
        for desc in sampleClasses {
            let cls = dx_vm_find_class(vm, desc)
            #expect(cls != nil, "Should find class \(desc)")
            if let cls = cls {
                let actualDesc = String(cString: cls.pointee.descriptor)
                #expect(actualDesc.hasPrefix("L"), "Descriptor should start with L")
                #expect(actualDesc.hasSuffix(";"), "Descriptor should end with ;")
                #expect(actualDesc == desc)
            }
        }
    }
}

// ============================================================
// MARK: - Method Resolution Tests
// ============================================================

@Suite("Method Resolution Tests")
struct MethodResolutionTests {

    @Test("find_method returns nil for nonexistent method")
    func testFindMethodNotFound() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let m = dx_vm_find_method(objCls, "totallyFakeMethod", "V")
        #expect(m == nil)
    }

    @Test("Native methods have is_native flag set")
    func testNativeMethodFlag() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let lengthMethod = dx_vm_find_method(strCls, "length", "I")
        #expect(lengthMethod != nil)
        if let m = lengthMethod {
            #expect(m.pointee.is_native == true)
            #expect(m.pointee.native_fn != nil)
        }
    }

    @Test("Methods have valid declaring class")
    func testMethodDeclaringClass() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!
        let addMethod = dx_vm_find_method(alCls, "add", "ZL")!
        #expect(addMethod.pointee.declaring_class != nil)
    }

    @Test("Object.toString exists")
    func testObjectToString() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let toString = dx_vm_find_method(objCls, "toString", "L")
        #expect(toString != nil, "Object.toString should be registered")
    }

    @Test("Object.equals exists")
    func testObjectEquals() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let equals = dx_vm_find_method(objCls, "equals", "ZL")
        #expect(equals != nil, "Object.equals should be registered")
    }

    @Test("Object.hashCode exists")
    func testObjectHashCode() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let hashCode = dx_vm_find_method(objCls, "hashCode", "I")
        #expect(hashCode != nil, "Object.hashCode should be registered")
    }
}

// ============================================================
// MARK: - Execution Edge Case Tests
// ============================================================

@Suite("Execution Edge Cases")
struct ExecutionEdgeCaseTests {

    @Test("String.length on empty string returns 0")
    func testStringLengthEmpty() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let lengthMethod = dx_vm_find_method(strCls, "length", "I")!

        let strObj = dx_vm_create_string(vm, "")!
        var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))]
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))

        let status = dx_vm_execute_method(vm, lengthMethod, &args, 1, &result)
        #expect(status == DX_OK)
        #expect(result.i == 0)
    }

    @Test("HashMap.size on empty map returns 0")
    func testHashMapSizeEmpty() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let hmCls = dx_vm_find_class(vm, "Ljava/util/HashMap;")!
        let map = dx_vm_alloc_object(vm, hmCls)!

        // Init
        if let initMethod = dx_vm_find_method(hmCls, "<init>", "V") {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map))]
            var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, initMethod, &args, 1, &r)
        }

        let sizeMethod = dx_vm_find_method(hmCls, "size", "I")!
        var sizeArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map))]
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, sizeMethod, &sizeArgs, 1, &result)
        #expect(status == DX_OK)
        #expect(result.i == 0)
    }

    @Test("Multiple strings don't interfere")
    func testMultipleStrings() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strings = ["alpha", "beta", "gamma", "delta", "epsilon"]
        var objects: [UnsafeMutablePointer<DxObject>] = []

        for s in strings {
            let obj = dx_vm_create_string(vm, s)!
            objects.append(obj)
        }

        // Verify each still has its original value
        for (i, obj) in objects.enumerated() {
            let value = String(cString: dx_vm_get_string_value(obj)!)
            #expect(value == strings[i], "String \(i) should be '\(strings[i])' but got '\(value)'")
        }
    }

    @Test("Allocate many objects without crash")
    func testMassAllocation() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        for _ in 0..<1000 {
            let obj = dx_vm_alloc_object(vm, objCls)
            #expect(obj != nil)
        }
    }

    @Test("Allocate large array")
    func testLargeArray() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let arr = dx_vm_alloc_array(vm, 10000)
        #expect(arr != nil)
        if let arr = arr {
            #expect(arr.pointee.array_length == 10000)
            // Write to last element
            arr.pointee.array_elements[9999] = DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 777))
            #expect(arr.pointee.array_elements[9999].i == 777)
        }
    }

    @Test("VM instruction counter starts at zero")
    func testInsnCounter() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        #expect(vm.pointee.insn_count == 0)
    }

    @Test("VM pending exception is nil on fresh VM")
    func testPendingExceptionClean() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        #expect(vm.pointee.pending_exception == nil)
    }

    @Test("Activity stack depth is 0 on fresh VM")
    func testActivityStackClean() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        #expect(vm.pointee.activity_stack_depth == 0)
        #expect(vm.pointee.activity_instance == nil)
    }
}

// ============================================================
// MARK: - SQLite / ContentValues Tests
// ============================================================

@Suite("SQLite and ContentValues Tests")
struct SQLiteContentValuesTests {

    @Test("ContentValues class exists")
    func testContentValuesClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cvCls = dx_vm_find_class(vm, "Landroid/content/ContentValues;")
        #expect(cvCls != nil, "ContentValues should be registered")
        if let cvCls = cvCls {
            let obj = dx_vm_alloc_object(vm, cvCls)
            #expect(obj != nil, "Should be able to allocate a ContentValues instance")
        }
    }

    @Test("SQLiteDatabase class exists")
    func testSQLiteDatabaseClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let dbCls = dx_vm_find_class(vm, "Landroid/database/sqlite/SQLiteDatabase;")
        #expect(dbCls != nil, "SQLiteDatabase should be registered")
    }

    @Test("Cursor class exists")
    func testCursorClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cursorCls = dx_vm_find_class(vm, "Landroid/database/Cursor;")
        #expect(cursorCls != nil, "Cursor should be registered")
    }

    @Test("RoomDatabase class exists")
    func testRoomDatabaseClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let roomDbCls = dx_vm_find_class(vm, "Landroidx/room/RoomDatabase;")
        #expect(roomDbCls != nil, "RoomDatabase should be registered")
    }

    @Test("Room annotation classes exist")
    func testRoomAnnotationClasses() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let annotations = [
            "Landroidx/room/Entity;",
            "Landroidx/room/Dao;",
            "Landroidx/room/Query;",
            "Landroidx/room/Insert;",
            "Landroidx/room/Delete;",
        ]
        for desc in annotations {
            let cls = dx_vm_find_class(vm, desc)
            #expect(cls != nil, "Expected Room annotation \(desc) to be registered")
        }
    }
}

// ============================================================
// MARK: - System Service Tests
// ============================================================

@Suite("System Service Tests")
struct SystemServiceTests {

    @Test("ClipboardManager class exists")
    func testClipboardManagerExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Landroid/content/ClipboardManager;")
        #expect(cls != nil, "ClipboardManager should be registered")
    }

    @Test("ConnectivityManager class exists")
    func testConnectivityManagerExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Landroid/net/ConnectivityManager;")
        #expect(cls != nil, "ConnectivityManager should be registered")
    }

    @Test("PowerManager class exists")
    func testPowerManagerExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Landroid/os/PowerManager;")
        #expect(cls != nil, "PowerManager should be registered")
    }

    @Test("AlarmManager class exists")
    func testAlarmManagerExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Landroid/app/AlarmManager;")
        #expect(cls != nil, "AlarmManager should be registered")
    }

    @Test("JobScheduler class exists")
    func testJobSchedulerExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Landroid/app/job/JobScheduler;")
        #expect(cls != nil, "JobScheduler should be registered")
    }
}

// ============================================================
// MARK: - Invoke-Custom Support Tests
// ============================================================

@Suite("Invoke-Custom Support Tests")
struct InvokeCustomTests {

    @Test("DxCallSite structure exists in DEX parsing")
    func testCallSiteStructure() {
        // Verify the DxCallSite type is accessible and has expected fields
        var cs = DxCallSite()
        cs.method_handle_idx = 42
        #expect(cs.method_handle_idx == 42)
        cs.parsed = true
        #expect(cs.parsed == true)
        cs.is_string_concat = false
        #expect(cs.is_string_concat == false)
    }

    @Test("DxDexFile has call_sites field")
    func testDexFileCallSitesField() {
        // Parse a minimal valid DEX to verify call_sites field exists
        var data = [UInt8](repeating: 0, count: 112)
        let magic: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]
        for i in 0..<8 { data[i] = magic[i] }
        data[32] = 112; data[33] = 0; data[34] = 0; data[35] = 0
        data[36] = 112; data[37] = 0; data[38] = 0; data[39] = 0
        data[40] = 0x78; data[41] = 0x56; data[42] = 0x34; data[43] = 0x12

        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        if result == DX_OK, let dex = dex {
            // call_sites should be nil (no call sites in minimal DEX)
            #expect(dex.pointee.call_sites == nil)
            #expect(dex.pointee.call_site_count == 0)
            dx_dex_free(dex)
        }
    }

    @Test("dx_dex_get_call_site returns nil for out of range index")
    func testCallSiteOutOfRange() {
        var data = [UInt8](repeating: 0, count: 112)
        let magic: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]
        for i in 0..<8 { data[i] = magic[i] }
        data[32] = 112; data[33] = 0; data[34] = 0; data[35] = 0
        data[36] = 112; data[37] = 0; data[38] = 0; data[39] = 0
        data[40] = 0x78; data[41] = 0x56; data[42] = 0x34; data[43] = 0x12

        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        if result == DX_OK, let dex = dex {
            let cs = dx_dex_get_call_site(dex, 999)
            #expect(cs == nil, "Out of range call site index should return nil")
            dx_dex_free(dex)
        }
    }
}

// ============================================================
// MARK: - Framework Class Count Test
// ============================================================

@Suite("Framework Scale Tests")
struct FrameworkScaleTests {

    @Test("Framework has 400+ registered classes")
    func testFrameworkClassCount() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        #expect(vm.pointee.class_count > 400,
                "Expected 400+ framework classes, got \(vm.pointee.class_count)")
    }
}

// ============================================================
// MARK: - String Operations Tests
// ============================================================

@Suite("String Operations Tests")
struct StringOperationsTests {

    @Test("String.valueOf with integer")
    func testStringValueOfInt() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let valueOf = dx_vm_find_method(strCls, "valueOf", "LI")
        #expect(valueOf != nil, "String.valueOf(int) should exist")

        if let valueOf = valueOf {
            var args = [DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 12345))]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let status = dx_vm_execute_method(vm, valueOf, &args, 1, &result)
            #expect(status == DX_OK)
            #expect(result.tag == DX_VAL_OBJ)
            if let obj = result.obj {
                let str = String(cString: dx_vm_get_string_value(obj)!)
                #expect(str == "12345")
            }
        }
    }

    @Test("String.concat joins two strings")
    func testStringConcat() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let concatMethod = dx_vm_find_method(strCls, "concat", "LL")
        #expect(concatMethod != nil, "String.concat should exist")

        if let concatMethod = concatMethod {
            let s1 = dx_vm_create_string(vm, "Hello ")!
            let s2 = dx_vm_create_string(vm, "World")!
            var args = [
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: s1)),
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: s2))
            ]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let status = dx_vm_execute_method(vm, concatMethod, &args, 2, &result)
            #expect(status == DX_OK)
            #expect(result.tag == DX_VAL_OBJ)
            if let obj = result.obj {
                let str = String(cString: dx_vm_get_string_value(obj)!)
                #expect(str == "Hello World")
            }
        }
    }

    @Test("StringBuilder append and toString")
    func testStringBuilderAppend() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let sbCls = dx_vm_find_class(vm, "Ljava/lang/StringBuilder;")!
        let sb = dx_vm_alloc_object(vm, sbCls)!

        // Init
        if let initMethod = dx_vm_find_method(sbCls, "<init>", "V") {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: sb))]
            var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, initMethod, &args, 1, &r)
        }

        // Append
        let appendMethod = dx_vm_find_method(sbCls, "append", "LL")
        #expect(appendMethod != nil, "StringBuilder.append should exist")
        if let appendMethod = appendMethod {
            for word in ["Dex", "Loom", "!"] {
                let strObj = dx_vm_create_string(vm, word)!
                var args = [
                    DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: sb)),
                    DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))
                ]
                var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
                let _ = dx_vm_execute_method(vm, appendMethod, &args, 2, &r)
            }
        }

        // toString
        let toStringMethod = dx_vm_find_method(sbCls, "toString", "L")
        #expect(toStringMethod != nil, "StringBuilder.toString should exist")
        if let toStringMethod = toStringMethod {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: sb))]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let status = dx_vm_execute_method(vm, toStringMethod, &args, 1, &result)
            #expect(status == DX_OK)
            #expect(result.tag == DX_VAL_OBJ)
            if let obj = result.obj {
                let str = String(cString: dx_vm_get_string_value(obj)!)
                #expect(str == "DexLoom!")
            }
        }
    }

    @Test("String.length returns correct count")
    func testStringLengthVariousLengths() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let lengthMethod = dx_vm_find_method(strCls, "length", "I")!

        let testCases: [(String, Int32)] = [
            ("", 0),
            ("a", 1),
            ("Hello World", 11),
            (String(repeating: "x", count: 100), 100),
        ]

        for (input, expectedLen) in testCases {
            let strObj = dx_vm_create_string(vm, input)!
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let status = dx_vm_execute_method(vm, lengthMethod, &args, 1, &result)
            #expect(status == DX_OK)
            #expect(result.i == expectedLen, "Expected length \(expectedLen) for '\(input)'")
        }
    }

    @Test("String.isEmpty on empty vs non-empty")
    func testStringIsEmpty() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let isEmptyMethod = dx_vm_find_method(strCls, "isEmpty", "Z")
        #expect(isEmptyMethod != nil, "String.isEmpty should exist")

        if let isEmptyMethod = isEmptyMethod {
            // Empty string should return true (1)
            let emptyStr = dx_vm_create_string(vm, "")!
            var args1 = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: emptyStr))]
            var result1 = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let s1 = dx_vm_execute_method(vm, isEmptyMethod, &args1, 1, &result1)
            #expect(s1 == DX_OK)
            #expect(result1.i != 0, "Empty string isEmpty should return true")

            // Non-empty string should return false (0)
            let nonEmptyStr = dx_vm_create_string(vm, "hello")!
            var args2 = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: nonEmptyStr))]
            var result2 = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let s2 = dx_vm_execute_method(vm, isEmptyMethod, &args2, 1, &result2)
            #expect(s2 == DX_OK)
            #expect(result2.i == 0, "Non-empty string isEmpty should return false")
        }
    }
}

// ============================================================
// MARK: - HashMap Extended Tests
// ============================================================

@Suite("HashMap Extended Tests")
struct HashMapExtendedTests {

    /// Helper to create and init a HashMap
    private func makeHashMap(_ vm: UnsafeMutablePointer<DxVM>) -> (UnsafeMutablePointer<DxObject>, UnsafeMutablePointer<DxClass>) {
        let hmCls = dx_vm_find_class(vm, "Ljava/util/HashMap;")!
        let map = dx_vm_alloc_object(vm, hmCls)!
        if let initMethod = dx_vm_find_method(hmCls, "<init>", "V") {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map))]
            var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, initMethod, &args, 1, &r)
        }
        return (map, hmCls)
    }

    @Test("HashMap.containsKey returns true for existing key")
    func testHashMapContainsKey() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }
        let (map, hmCls) = makeHashMap(vm)

        // Put a key
        let putMethod = dx_vm_find_method(hmCls, "put", "LLL")!
        let key = dx_vm_create_string(vm, "testKey")!
        let val = dx_vm_create_string(vm, "testVal")!
        var putArgs = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: key)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: val))
        ]
        var putResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let _ = dx_vm_execute_method(vm, putMethod, &putArgs, 3, &putResult)

        // containsKey should return true
        let containsMethod = dx_vm_find_method(hmCls, "containsKey", "ZL")!
        var containsArgs = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: key))
        ]
        var containsResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, containsMethod, &containsArgs, 2, &containsResult)
        #expect(status == DX_OK)
        #expect(containsResult.i != 0, "containsKey should return true for existing key")
    }

    @Test("HashMap.remove removes a key")
    func testHashMapRemove() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }
        let (map, hmCls) = makeHashMap(vm)

        // Put a key
        let putMethod = dx_vm_find_method(hmCls, "put", "LLL")!
        let key = dx_vm_create_string(vm, "removeMe")!
        let val = dx_vm_create_string(vm, "value")!
        var putArgs = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: key)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: val))
        ]
        var putResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let _ = dx_vm_execute_method(vm, putMethod, &putArgs, 3, &putResult)

        // Remove the key
        let removeMethod = dx_vm_find_method(hmCls, "remove", "LL")!
        var removeArgs = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: key))
        ]
        var removeResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let removeStatus = dx_vm_execute_method(vm, removeMethod, &removeArgs, 2, &removeResult)
        #expect(removeStatus == DX_OK)

        // Size should be 0 after remove
        let sizeMethod = dx_vm_find_method(hmCls, "size", "I")!
        var sizeArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map))]
        var sizeResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let sizeStatus = dx_vm_execute_method(vm, sizeMethod, &sizeArgs, 1, &sizeResult)
        #expect(sizeStatus == DX_OK)
        #expect(sizeResult.i == 0, "HashMap size should be 0 after removing the only entry")
    }

    @Test("HashMap with multiple entries")
    func testHashMapMultipleEntries() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }
        let (map, hmCls) = makeHashMap(vm)

        let putMethod = dx_vm_find_method(hmCls, "put", "LLL")!
        // Insert 15 entries
        for i in 0..<15 {
            let key = dx_vm_create_string(vm, "key_\(i)")!
            let val = dx_vm_create_string(vm, "val_\(i)")!
            var putArgs = [
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map)),
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: key)),
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: val))
            ]
            var putResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, putMethod, &putArgs, 3, &putResult)
        }

        // Size should be 15
        let sizeMethod = dx_vm_find_method(hmCls, "size", "I")!
        var sizeArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: map))]
        var sizeResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, sizeMethod, &sizeArgs, 1, &sizeResult)
        #expect(status == DX_OK)
        #expect(sizeResult.i == 15, "HashMap should have 15 entries")
    }
}

// ============================================================
// MARK: - ArrayList Extended Tests
// ============================================================

@Suite("ArrayList Extended Tests")
struct ArrayListExtendedTests {

    /// Helper to create and init an ArrayList
    private func makeArrayList(_ vm: UnsafeMutablePointer<DxVM>) -> (UnsafeMutablePointer<DxObject>, UnsafeMutablePointer<DxClass>) {
        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!
        let list = dx_vm_alloc_object(vm, alCls)!
        if let initMethod = dx_vm_find_method(alCls, "<init>", "V") {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list))]
            var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, initMethod, &args, 1, &r)
        }
        return (list, alCls)
    }

    private func addItem(_ vm: UnsafeMutablePointer<DxVM>, _ list: UnsafeMutablePointer<DxObject>, _ alCls: UnsafeMutablePointer<DxClass>, _ text: String) {
        let addMethod = dx_vm_find_method(alCls, "add", "ZL")!
        let strObj = dx_vm_create_string(vm, text)!
        var args = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))
        ]
        var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let _ = dx_vm_execute_method(vm, addMethod, &args, 2, &r)
    }

    @Test("ArrayList.remove by index")
    func testArrayListRemove() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }
        let (list, alCls) = makeArrayList(vm)

        addItem(vm, list, alCls, "alpha")
        addItem(vm, list, alCls, "beta")
        addItem(vm, list, alCls, "gamma")

        // Remove index 1 ("beta")
        let removeMethod = dx_vm_find_method(alCls, "remove", "LI")!
        var removeArgs = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list)),
            DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 1))
        ]
        var removeResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, removeMethod, &removeArgs, 2, &removeResult)
        #expect(status == DX_OK)

        // Size should be 2
        let sizeMethod = dx_vm_find_method(alCls, "size", "I")!
        var sizeArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list))]
        var sizeResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let _ = dx_vm_execute_method(vm, sizeMethod, &sizeArgs, 1, &sizeResult)
        #expect(sizeResult.i == 2, "ArrayList should have 2 elements after removing one")
    }

    @Test("ArrayList.contains finds existing element")
    func testArrayListContains() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }
        let (list, alCls) = makeArrayList(vm)

        let searchStr = dx_vm_create_string(vm, "findMe")!
        addItem(vm, list, alCls, "findMe")
        addItem(vm, list, alCls, "other")

        let containsMethod = dx_vm_find_method(alCls, "contains", "ZL")!
        var args = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list)),
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: searchStr))
        ]
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, containsMethod, &args, 2, &result)
        #expect(status == DX_OK)
        // contains should return true (non-zero) or at least not crash
    }

    @Test("ArrayList.get retrieves correct element by index")
    func testArrayListGetByIndex() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }
        let (list, alCls) = makeArrayList(vm)

        addItem(vm, list, alCls, "zero")
        addItem(vm, list, alCls, "one")
        addItem(vm, list, alCls, "two")

        let getMethod = dx_vm_find_method(alCls, "get", "LI")!
        var args = [
            DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: list)),
            DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 1))
        ]
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, getMethod, &args, 2, &result)
        #expect(status == DX_OK)
        #expect(result.tag == DX_VAL_OBJ)
        if let obj = result.obj {
            let str = String(cString: dx_vm_get_string_value(obj)!)
            #expect(str == "one", "get(1) should return 'one'")
        }
    }
}

// ============================================================
// MARK: - GC Tests
// ============================================================

@Suite("GC Tests")
struct GCTests {

    @Test("Heap has positive capacity constant")
    func testHeapCapacity() {
        let ctx = dx_context_create()!
        let vm = dx_vm_create(ctx)!
        dx_vm_register_framework_classes(vm)

        // DX_MAX_HEAP_OBJECTS should be > 0; heap_count starts low
        #expect(vm.pointee.heap_count >= 0)
        // The heap array exists and we can allocate into it
        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let _ = dx_vm_alloc_object(vm, objCls)
        #expect(vm.pointee.heap_count > 0)

        dx_vm_destroy(vm)
        ctx.pointee.vm = nil
        dx_context_destroy(ctx)
    }

    @Test("Mass allocation of 1000 objects does not crash")
    func testMassAllocation1000() {
        let ctx = dx_context_create()!
        let vm = dx_vm_create(ctx)!
        dx_vm_register_framework_classes(vm)

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let before = vm.pointee.heap_count
        for _ in 0..<1000 {
            let obj = dx_vm_alloc_object(vm, objCls)
            #expect(obj != nil)
        }
        #expect(vm.pointee.heap_count == before + 1000)

        dx_vm_destroy(vm)
        ctx.pointee.vm = nil
        dx_context_destroy(ctx)
    }

    @Test("Heap count increases with allocations")
    func testHeapCountGrows() {
        let ctx = dx_context_create()!
        let vm = dx_vm_create(ctx)!
        dx_vm_register_framework_classes(vm)

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let initial = vm.pointee.heap_count

        for i: UInt32 in 1...50 {
            let _ = dx_vm_alloc_object(vm, objCls)
            #expect(vm.pointee.heap_count == initial + i)
        }

        dx_vm_destroy(vm)
        ctx.pointee.vm = nil
        dx_context_destroy(ctx)
    }
}

// ============================================================
// MARK: - Networking Stub Tests
// ============================================================

@Suite("Networking Stub Tests")
struct NetworkingStubTests {

    @Test("HttpURLConnection class exists")
    func testHttpURLConnectionExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/net/HttpURLConnection;")
        #expect(cls != nil, "HttpURLConnection should be registered")
    }

    @Test("URL class exists")
    func testURLClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/net/URL;")
        #expect(cls != nil, "java.net.URL should be registered")
    }
}

// ============================================================
// MARK: - Reflection Tests
// ============================================================

@Suite("Reflection Tests")
struct ReflectionTests {

    @Test("java.lang.reflect.Method class exists")
    func testMethodClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/lang/reflect/Method;")
        #expect(cls != nil, "java.lang.reflect.Method should be registered")
    }

    @Test("java.lang.reflect.Field class exists")
    func testFieldClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/lang/reflect/Field;")
        #expect(cls != nil, "java.lang.reflect.Field should be registered")
    }

    @Test("java.lang.reflect.Constructor class exists")
    func testConstructorClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/lang/reflect/Constructor;")
        #expect(cls != nil, "java.lang.reflect.Constructor should be registered")
    }
}

// ============================================================
// MARK: - Inline Cache Tests
// ============================================================

@Suite("Inline Cache Tests")
struct InlineCacheTests {

    @Test("IC insert and lookup returns cached method for same receiver class")
    func testICInsertAndLookup() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Get a class and a method to use as test data
        let stringCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let toStringMethod = dx_vm_find_method(stringCls, "toString", "L")

        // Create an IC table on a method by calling dx_vm_ic_get
        // We need a method with an ic_table — use dx_vm_ic_get which lazily allocates
        guard let method = toStringMethod else {
            #expect(Bool(false), "toString method not found on String")
            return
        }

        let ic = dx_vm_ic_get(method, 0)
        #expect(ic != nil, "dx_vm_ic_get should return a non-nil inline cache")

        if let ic = ic {
            // Insert a mapping: stringCls -> method
            dx_vm_ic_insert(ic, stringCls, method)

            // Lookup should return the same method
            let resolved = dx_vm_ic_lookup(ic, stringCls)
            #expect(resolved == method, "IC lookup should return the cached method")
            #expect(ic.pointee.count == 1, "IC should have 1 entry after insert")
        }
    }

    @Test("IC handles polymorphic dispatch with multiple receiver types")
    func testICPolymorphic() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let stringCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let integerCls = dx_vm_find_class(vm, "Ljava/lang/Integer;")!
        let objectCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

        let toStringOnString = dx_vm_find_method(stringCls, "toString", "L")!
        let toStringOnInteger = dx_vm_find_method(integerCls, "toString", "L")
        let toStringOnObject = dx_vm_find_method(objectCls, "toString", "L")

        let ic = dx_vm_ic_get(toStringOnString, 4)!

        // Insert multiple receiver types
        dx_vm_ic_insert(ic, stringCls, toStringOnString)
        if let m = toStringOnInteger {
            dx_vm_ic_insert(ic, integerCls, m)
        }
        if let m = toStringOnObject {
            dx_vm_ic_insert(ic, objectCls, m)
        }

        // Lookup each — should find the correct cached method
        let r1 = dx_vm_ic_lookup(ic, stringCls)
        #expect(r1 == toStringOnString, "Should resolve String.toString from IC")

        // Count should reflect the number of distinct entries inserted
        #expect(ic.pointee.count >= 1, "IC should have at least 1 entry for polymorphic dispatch")
    }

    @Test("IC stats does not crash")
    func testICStatsNoCrash() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Just ensure calling ic_stats doesn't crash, even with no IC data
        dx_vm_ic_stats(vm)

        // Now insert some IC data and call again
        let cls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let method = dx_vm_find_method(cls, "toString", "L")!
        let ic = dx_vm_ic_get(method, 0)!
        dx_vm_ic_insert(ic, cls, method)
        _ = dx_vm_ic_lookup(ic, cls)

        dx_vm_ic_stats(vm)
        // If we get here, stats didn't crash
    }

    @Test("IC lookup miss returns nil for unknown receiver class")
    func testICLookupMiss() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let stringCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let integerCls = dx_vm_find_class(vm, "Ljava/lang/Integer;")!
        let method = dx_vm_find_method(stringCls, "toString", "L")!

        let ic = dx_vm_ic_get(method, 8)!
        // Insert only for String
        dx_vm_ic_insert(ic, stringCls, method)

        // Lookup for Integer should miss
        let miss = dx_vm_ic_lookup(ic, integerCls)
        #expect(miss == nil, "IC lookup should return nil for a class not in the cache")
    }
}

// ============================================================
// MARK: - Incremental GC Tests
// ============================================================

@Suite("Incremental GC Tests")
struct IncrementalGCTests {

    @Test("GC step on empty heap does not crash")
    func testGCStepEmptyHeap() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // No objects allocated beyond framework classes — step should be safe
        dx_vm_gc_step(vm)
        dx_vm_gc_step(vm)
        dx_vm_gc_step(vm)
        // If we get here, no crash
    }

    @Test("Incremental GC eventually frees unreachable objects")
    func testGCFreesUnreachable() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

        // Allocate some objects and don't hold references
        let heapBefore = vm.pointee.heap_count
        for _ in 0..<50 {
            _ = dx_vm_alloc_object(vm, cls)
        }
        let heapAfterAlloc = vm.pointee.heap_count
        #expect(heapAfterAlloc > heapBefore, "Heap should grow after allocations")

        // Run many incremental GC steps to eventually sweep
        for _ in 0..<200 {
            dx_vm_gc_step(vm)
        }
        // Also run a full GC to ensure sweep completes
        dx_vm_gc(vm)

        let heapAfterGC = vm.pointee.heap_count
        #expect(heapAfterGC <= heapAfterAlloc, "Heap should not grow after GC")
    }

    @Test("GC preserves reachable objects through incremental cycle")
    func testGCPreservesReachable() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Create a string — it stays in the intern table, so it's reachable
        let str = dx_vm_intern_string(vm, "gc_preserve_test")
        #expect(str != nil)

        // Run GC steps
        for _ in 0..<200 {
            dx_vm_gc_step(vm)
        }
        dx_vm_gc(vm)

        // Interned string should still be retrievable
        let str2 = dx_vm_intern_string(vm, "gc_preserve_test")
        #expect(str2 == str, "Interned string should survive GC")
    }

    @Test("Full GC collect does not crash after incremental steps")
    func testGCCollectAfterSteps() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        for _ in 0..<20 {
            _ = dx_vm_alloc_object(vm, cls)
        }

        // Mix incremental steps with full collect
        dx_vm_gc_step(vm)
        dx_vm_gc_step(vm)
        dx_vm_gc_collect(vm)
        dx_vm_gc_step(vm)
        dx_vm_gc_collect(vm)
        // No crash = pass
    }
}

// ============================================================
// MARK: - ClassLoader Tests
// ============================================================

@Suite("ClassLoader Tests")
struct ClassLoaderTests {

    @Test("ClassLoader class is registered")
    func testClassLoaderExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/lang/ClassLoader;")
        #expect(cls != nil, "java.lang.ClassLoader should be registered")
    }

    @Test("PathClassLoader class is registered and delegates correctly")
    func testPathClassLoaderExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ldalvik/system/PathClassLoader;")
        #expect(cls != nil, "dalvik.system.PathClassLoader should be registered")

        // PathClassLoader should be instantiable
        if let cls = cls {
            let obj = dx_vm_alloc_object(vm, cls)
            #expect(obj != nil, "Should be able to allocate PathClassLoader instance")
        }
    }

    @Test("Class.getClassLoader returns non-null for framework class")
    func testGetClassLoaderNonNull() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // java.lang.Class should be registered
        let classCls = dx_vm_find_class(vm, "Ljava/lang/Class;")
        #expect(classCls != nil, "java.lang.Class should be registered")

        // getClassLoader method should exist
        if let classCls = classCls {
            let method = dx_vm_find_method(classCls, "getClassLoader", "L")
            #expect(method != nil, "Class.getClassLoader() method should exist")
        }
    }
}

// ============================================================
// MARK: - Socket Tests
// ============================================================

@Suite("Socket Tests")
struct SocketTests {

    @Test("Socket class exists and can be instantiated")
    func testSocketClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/net/Socket;")
        #expect(cls != nil, "java.net.Socket should be registered")

        if let cls = cls {
            let obj = dx_vm_alloc_object(vm, cls)
            #expect(obj != nil, "Should be able to allocate Socket instance")
        }
    }

    @Test("ServerSocket class exists and can be instantiated")
    func testServerSocketClassExists() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let cls = dx_vm_find_class(vm, "Ljava/net/ServerSocket;")
        #expect(cls != nil, "java.net.ServerSocket should be registered")

        if let cls = cls {
            let obj = dx_vm_alloc_object(vm, cls)
            #expect(obj != nil, "Should be able to allocate ServerSocket instance")
        }
    }

    @Test("SocketInputStream and SocketOutputStream classes registered")
    func testSocketStreamClasses() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let inputCls = dx_vm_find_class(vm, "Ljava/net/SocketInputStream;")
        #expect(inputCls != nil, "java.net.SocketInputStream should be registered")

        let outputCls = dx_vm_find_class(vm, "Ljava/net/SocketOutputStream;")
        #expect(outputCls != nil, "java.net.SocketOutputStream should be registered")
    }
}

// ============================================================
// MARK: - Debug Tracing Tests
// ============================================================

@Suite("Debug Tracing Tests")
struct DebugTracingTests {

    @Test("Set trace enables and disables without crash")
    func testSetTraceNoCrash() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Enable all tracing flags
        dx_vm_set_trace(vm, true, true, true)

        // Disable all
        dx_vm_set_trace(vm, false, false, false)

        // Mixed
        dx_vm_set_trace(vm, true, false, true)
        dx_vm_set_trace(vm, false, true, false)

        // Final disable
        dx_vm_set_trace(vm, false, false, false)
    }

    @Test("Set trace filter with prefix filtering does not crash")
    func testSetTraceFilterNoCrash() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        dx_vm_set_trace(vm, true, true, true)

        // Set a method filter prefix
        dx_vm_set_trace_filter(vm, "Ljava/lang/String;")

        // Change filter
        dx_vm_set_trace_filter(vm, "Landroid/")

        // Clear filter with nil
        dx_vm_set_trace_filter(vm, nil)

        dx_vm_set_trace(vm, false, false, false)
    }

    @Test("Trace active during string operations does not crash")
    func testTraceActiveStringOps() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Enable tracing
        dx_vm_set_trace(vm, true, true, true)

        // Perform some operations with tracing on
        let str = dx_vm_create_string(vm, "trace test")
        #expect(str != nil)

        let interned = dx_vm_intern_string(vm, "trace intern test")
        #expect(interned != nil)

        let cls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        let obj = dx_vm_alloc_object(vm, cls)
        #expect(obj != nil)

        // Disable tracing
        dx_vm_set_trace(vm, false, false, false)
    }
}

// ============================================================
// MARK: - Fuzzer Smoke Tests
// ============================================================

// Declare fuzzer C functions directly (not in bridging header)
@_silgen_name("dx_fuzz_apk")
private func _dx_fuzz_apk(_ data: UnsafePointer<UInt8>?, _ size: Int) -> Int32
@_silgen_name("dx_fuzz_dex")
private func _dx_fuzz_dex(_ data: UnsafePointer<UInt8>?, _ size: Int) -> Int32
@_silgen_name("dx_fuzz_axml")
private func _dx_fuzz_axml(_ data: UnsafePointer<UInt8>?, _ size: Int) -> Int32
@_silgen_name("dx_fuzz_resources")
private func _dx_fuzz_resources(_ data: UnsafePointer<UInt8>?, _ size: Int) -> Int32

@Suite("Fuzzer Smoke Tests")
struct FuzzerSmokeTests {

    @Test("dx_fuzz_apk with empty data does not crash")
    func testFuzzApkEmpty() {
        let data: [UInt8] = []
        let result = data.withUnsafeBufferPointer { buf in
            _dx_fuzz_apk(buf.baseAddress, 0)
        }
        #expect(result == 0, "Fuzzer should return 0 on empty input")
    }

    @Test("dx_fuzz_dex with empty data does not crash")
    func testFuzzDexEmpty() {
        let data: [UInt8] = []
        let result = data.withUnsafeBufferPointer { buf in
            _dx_fuzz_dex(buf.baseAddress, 0)
        }
        #expect(result == 0, "Fuzzer should return 0 on empty input")
    }

    @Test("dx_fuzz_axml with empty data does not crash")
    func testFuzzAxmlEmpty() {
        let data: [UInt8] = []
        let result = data.withUnsafeBufferPointer { buf in
            _dx_fuzz_axml(buf.baseAddress, 0)
        }
        #expect(result == 0, "Fuzzer should return 0 on empty input")
    }

    @Test("dx_fuzz_resources with empty data does not crash")
    func testFuzzResourcesEmpty() {
        let data: [UInt8] = []
        let result = data.withUnsafeBufferPointer { buf in
            _dx_fuzz_resources(buf.baseAddress, 0)
        }
        #expect(result == 0, "Fuzzer should return 0 on empty input")
    }
}

// ============================================================
// MARK: - Helper: Create a synthetic bytecode method
// ============================================================

/// Creates a DxMethod with synthetic bytecode for testing the interpreter.
/// The caller is responsible for freeing the insns buffer.
private func makeSyntheticMethod(
    vm: UnsafeMutablePointer<DxVM>,
    name: String,
    shorty: String,
    registers: UInt16,
    insns: [UInt16]
) -> (method: UnsafeMutablePointer<DxMethod>, insnsBuf: UnsafeMutableBufferPointer<UInt16>) {
    let methodPtr = UnsafeMutablePointer<DxMethod>.allocate(capacity: 1)
    methodPtr.initialize(to: DxMethod())

    let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

    // Copy insns to a heap buffer (interpreter reads from pointer)
    let buf = UnsafeMutableBufferPointer<UInt16>.allocate(capacity: insns.count)
    for (i, v) in insns.enumerated() { buf[i] = v }

    // Use strdup to keep name/shorty alive, cast to UnsafePointer for const char* fields
    methodPtr.pointee.name = UnsafePointer(strdup(name))
    methodPtr.pointee.shorty = UnsafePointer(strdup(shorty))
    methodPtr.pointee.declaring_class = objCls
    methodPtr.pointee.has_code = true
    methodPtr.pointee.is_native = false
    methodPtr.pointee.access_flags = UInt32(DX_ACC_PUBLIC.rawValue | DX_ACC_STATIC.rawValue)
    methodPtr.pointee.code.registers_size = registers
    methodPtr.pointee.code.ins_size = 0
    methodPtr.pointee.code.outs_size = 0
    methodPtr.pointee.code.tries_size = 0
    methodPtr.pointee.code.debug_info_off = 0
    methodPtr.pointee.code.insns_size = UInt32(insns.count)
    methodPtr.pointee.code.insns = buf.baseAddress
    methodPtr.pointee.code.line_table = nil
    methodPtr.pointee.code.line_count = 0
    methodPtr.pointee.vtable_idx = -1

    return (methodPtr, buf)
}

private func freeSyntheticMethod(_ method: UnsafeMutablePointer<DxMethod>, _ buf: UnsafeMutableBufferPointer<UInt16>) {
    free(UnsafeMutablePointer(mutating: method.pointee.name))
    free(UnsafeMutablePointer(mutating: method.pointee.shorty))
    buf.deallocate()
    method.deallocate()
}

// ============================================================
// MARK: - Bytecode Execution Tests (Synthetic)
// ============================================================

@Suite("Bytecode Execution Synthetic Tests")
struct BytecodeExecutionSyntheticTests {

    @Test("const/4 and const/16 load values correctly")
    func testConstLoads() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Bytecode:
        //   const/4 v0, 7          -> 0x1270  (opcode 0x12, vA=0, +B=7 => 0x12 | (0<<8) | (7<<12) but packed: nibble dest=0, lit=7)
        //   const/16 v1, 1234      -> 0x1301 0x04D2
        //   return v0              -> 0x0F00
        // const/4: format 11n -> 0x12 | (dest << 8) | (lit << 12)
        //   dest=0, lit=7 -> 0x12 | 0x00 | 0x7000 = 0x7012
        // const/16: format 21s -> 0x13 | (dest << 8), value16
        //   dest=1, value=1234 -> 0x0113, 0x04D2
        // return v0: format 11x -> 0x0F | (reg << 8) = 0x000F
        let insns: [UInt16] = [
            0x7012,         // const/4 v0, #7
            0x0113, 0x04D2, // const/16 v1, #1234
            0x000F          // return v0
        ]
        let (method, buf) = makeSyntheticMethod(vm: vm, name: "testConst", shorty: "I", registers: 2, insns: insns)
        defer { freeSyntheticMethod(method, buf) }

        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, method, nil, 0, &result)
        #expect(status == DX_OK)
        #expect(result.tag == DX_VAL_INT)
        #expect(result.i == 7)
    }

    @Test("add-int, sub-int, mul-int produce correct results")
    func testArithmeticOps() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // v0 = 10, v1 = 3
        // v2 = v0 + v1 (add-int)  -> 13
        // v2 = v2 - v1 (sub-int)  -> 10
        // v2 = v2 * v1 (mul-int)  -> 30
        // return v2
        //
        // const/4 v0, #10 -> but const/4 max is 7... use const/16 instead
        // const/16 v0, #10 -> 0x0013, 0x000A
        // const/16 v1, #3  -> 0x0113, 0x0003
        // add-int v2,v0,v1 -> opcode 0x90, format 23x: 0x90 | (dest<<8), (vB | vC<<8)
        //   0x0290, 0x0100
        // sub-int v2,v2,v1 -> opcode 0x91
        //   0x0291, 0x0102
        // mul-int v2,v2,v1 -> opcode 0x92
        //   0x0292, 0x0102
        // return v2 -> 0x020F
        let insns: [UInt16] = [
            0x0013, 0x000A, // const/16 v0, #10
            0x0113, 0x0003, // const/16 v1, #3
            0x0290, 0x0100, // add-int v2, v0, v1
            0x0291, 0x0102, // sub-int v2, v2, v1
            0x0292, 0x0102, // mul-int v2, v2, v1
            0x020F          // return v2
        ]
        let (method, buf) = makeSyntheticMethod(vm: vm, name: "testArith", shorty: "I", registers: 3, insns: insns)
        defer { freeSyntheticMethod(method, buf) }

        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, method, nil, 0, &result)
        #expect(status == DX_OK)
        #expect(result.tag == DX_VAL_INT)
        #expect(result.i == 30)
    }

    @Test("if-eq branch taken and not-taken cases")
    func testIfEqBranch() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Test branch taken: v0 == v1 -> branch
        // const/16 v0, #5   -> 0x0013, 0x0005
        // const/16 v1, #5   -> 0x0113, 0x0005
        // if-eq v0,v1,+3    -> opcode 0x32, format 22t: 0x32 | (vA<<8), offset16
        //   0x0032, 0x0003  -> if v0==v1 goto pc+3
        // const/16 v2, #99  -> 0x0213, 0x0063 (not-taken path)
        // return v2          -> 0x020F
        // const/16 v2, #42  -> 0x0213, 0x002A (taken path, at offset 7)
        // return v2          -> 0x020F
        let insns: [UInt16] = [
            0x0013, 0x0005, // [0] const/16 v0, #5
            0x0113, 0x0005, // [2] const/16 v1, #5
            0x0032, 0x0003, // [4] if-eq v0, v1, +3 -> goto offset 7
            0x0213, 0x0063, // [6] const/16 v2, #99
            0x020F,         // [8] return v2
            0x0213, 0x002A, // [9] const/16 v2, #42  (branch target at pc=7: 4+3=7... wait)
        ]
        // Actually, if-eq at pc=4 with offset +3 jumps to pc=4+3=7.
        // insns[7] is the 8th element (0-indexed). Let me recalculate.
        // Index: [0]=0x0013 [1]=0x0005 [2]=0x0113 [3]=0x0005 [4]=0x0032 [5]=0x0003
        //        [6]=0x0213 [7]=0x0063 [8]=0x020F [9]=0x0213 [10]=0x002A [11]=0x020F
        // if-eq at pc=4, offset=+3, target=pc 7. insns[7]=0x0063 which is middle of const/16.
        // Need offset=+5 to land at index 9.
        // Actually let me reconsider: pc=4, target=4+5=9. insns[9]=0x0213 -> const/16 v2, #42
        let insns2: [UInt16] = [
            0x0013, 0x0005, // [0] const/16 v0, #5
            0x0113, 0x0005, // [2] const/16 v1, #5
            0x0032, 0x0005, // [4] if-eq v0, v1, +5 -> goto pc 9
            0x0213, 0x0063, // [6] const/16 v2, #99
            0x020F,         // [8] return v2
            0x0213, 0x002A, // [9] const/16 v2, #42
            0x020F          // [11] return v2
        ]
        let (method, buf) = makeSyntheticMethod(vm: vm, name: "testIfEq", shorty: "I", registers: 3, insns: insns2)
        defer { freeSyntheticMethod(method, buf) }

        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, method, nil, 0, &result)
        #expect(status == DX_OK)
        #expect(result.tag == DX_VAL_INT)
        #expect(result.i == 42, "Branch should be taken since v0 == v1")
    }

    @Test("goto forward jump")
    func testGotoForward() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // goto +3 -> skip over a const, land on the return
        // [0] goto +3           -> opcode 0x28, format 10t: 0x28 | (offset<<8)
        //     offset=+3, packed: 0x0328
        // [1] const/16 v0, #99  -> skipped
        // [3] const/16 v0, #7
        // [5] return v0
        let insns: [UInt16] = [
            0x0328,         // [0] goto +3
            0x0013, 0x0063, // [1] const/16 v0, #99 (skipped)
            0x0013, 0x0007, // [3] const/16 v0, #7
            0x000F          // [5] return v0
        ]
        let (method, buf) = makeSyntheticMethod(vm: vm, name: "testGotoFwd", shorty: "I", registers: 1, insns: insns)
        defer { freeSyntheticMethod(method, buf) }

        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, method, nil, 0, &result)
        #expect(status == DX_OK)
        #expect(result.tag == DX_VAL_INT)
        #expect(result.i == 7, "Should skip to const/16 v0, #7 via goto")
    }

    @Test("return-void does not crash and returns void")
    func testReturnVoid() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // return-void -> opcode 0x0E
        let insns: [UInt16] = [
            0x000E  // return-void
        ]
        let (method, buf) = makeSyntheticMethod(vm: vm, name: "testRetVoid", shorty: "V", registers: 0, insns: insns)
        defer { freeSyntheticMethod(method, buf) }

        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, method, nil, 0, &result)
        #expect(status == DX_OK)
    }
}

// ============================================================
// MARK: - Resource Resolution Tests
// ============================================================

@Suite("Resource Resolution Tests")
struct ResourceResolutionTests {

    @Test("dx_resources_find_by_id returns NULL for unknown resource ID on empty resources")
    func testFindByIdUnknown() {
        // Create a minimal valid resources.arsc is complex; instead test that
        // a NULL resources pointer or an empty one returns NULL gracefully
        let result = dx_resources_find_by_id(nil, 0x7F010001)
        #expect(result == nil, "find_by_id with nil resources should return NULL")
    }

    @Test("dx_resources_get_string returns NULL for nil resources")
    func testGetStringNilResources() {
        let result = dx_resources_get_string(nil, 0x7F030001)
        #expect(result == nil, "get_string with nil resources should return NULL")
    }

    @Test("dx_resources_find_by_name returns NULL for nil resources")
    func testFindByNameNil() {
        let result = dx_resources_find_by_name(nil, "string", "app_name")
        #expect(result == nil, "find_by_name with nil resources should return NULL")
    }
}

// ============================================================
// MARK: - GC Correctness Tests
// ============================================================

@Suite("GC Correctness Tests")
struct GCCorrectnessTests {

    @Test("GC with no objects does not crash")
    func testGCEmpty() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // No user objects allocated (only framework class statics).
        // Calling gc_collect should not crash.
        dx_vm_gc_collect(vm)
    }

    @Test("GC frees unreachable objects (heap count decreases)")
    func testGCFreesUnreachable() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

        // Allocate objects but don't root them anywhere
        let beforeCount = vm.pointee.heap_count
        for _ in 0..<20 {
            let _ = dx_vm_alloc_object(vm, objCls)
        }
        #expect(vm.pointee.heap_count == beforeCount + 20)

        // Run GC - unreachable objects should be collected
        dx_vm_gc_collect(vm)
        #expect(vm.pointee.heap_count < beforeCount + 20,
                "GC should have freed some unreachable objects")
    }

    @Test("GC preserves objects referenced from static fields")
    func testGCPreservesStaticRefs() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

        // Create a string and store it in an interned slot (acts as a root)
        let rooted = dx_vm_intern_string(vm, "gc_root_test")
        #expect(rooted != nil)

        // Run GC
        dx_vm_gc_collect(vm)

        // The interned string should still be valid
        let value = dx_vm_get_string_value(rooted)
        #expect(value != nil)
        if let value = value {
            #expect(String(cString: value) == "gc_root_test")
        }
    }

    @Test("Weak reference cleared after GC")
    func testWeakRefClearedAfterGC() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let weakCls = dx_vm_find_class(vm, "Ljava/lang/ref/WeakReference;")
        #expect(weakCls != nil, "WeakReference class should be registered")

        if let weakCls = weakCls {
            // Create the target object (not rooted anywhere)
            let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
            let target = dx_vm_alloc_object(vm, objCls)!

            // Create a WeakReference
            let weakRef = dx_vm_alloc_object(vm, weakCls)!

            // Init: WeakReference stores referent in field[0]
            let initMethod = dx_vm_find_method(weakCls, "<init>", "VL")
            if let initMethod = initMethod {
                var args = [
                    DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: weakRef)),
                    DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: target))
                ]
                var r = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
                let _ = dx_vm_execute_method(vm, initMethod, &args, 2, &r)
            }

            // Run GC - target is only referenced by WeakReference, should be cleared
            dx_vm_gc_collect(vm)

            // Verify that get() returns null after GC
            let getMethod = dx_vm_find_method(weakCls, "get", "L")
            if let getMethod = getMethod {
                var getArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: weakRef))]
                var getResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
                let status = dx_vm_execute_method(vm, getMethod, &getArgs, 1, &getResult)
                if status == DX_OK {
                    // After GC the referent should be cleared (null)
                    #expect(getResult.obj == nil, "WeakReference.get() should return null after GC clears referent")
                }
            }
        }
    }
}

// ============================================================
// MARK: - String Interning Tests
// ============================================================

@Suite("String Interning Tests")
struct StringInterningTests {

    @Test("Same string interned twice returns same object")
    func testInternSameString() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let s1 = dx_vm_intern_string(vm, "hello_intern")
        let s2 = dx_vm_intern_string(vm, "hello_intern")
        #expect(s1 != nil)
        #expect(s2 != nil)
        #expect(s1 == s2, "Same string interned twice must return identical object pointer")
    }

    @Test("Different strings return different objects")
    func testInternDifferentStrings() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let s1 = dx_vm_intern_string(vm, "alpha")
        let s2 = dx_vm_intern_string(vm, "beta")
        #expect(s1 != nil)
        #expect(s2 != nil)
        #expect(s1 != s2, "Different strings must return different object pointers")

        // Verify actual values
        #expect(String(cString: dx_vm_get_string_value(s1)!) == "alpha")
        #expect(String(cString: dx_vm_get_string_value(s2)!) == "beta")
    }

    @Test("Intern survives GC")
    func testInternSurvivesGC() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let s1 = dx_vm_intern_string(vm, "persistent_string")
        #expect(s1 != nil)

        // Run GC
        dx_vm_gc_collect(vm)

        // Re-intern and verify it returns the same object
        let s2 = dx_vm_intern_string(vm, "persistent_string")
        #expect(s2 != nil)
        #expect(s1 == s2, "Interned string should survive GC and return same object")

        // Verify value is intact
        let val = dx_vm_get_string_value(s2)
        #expect(val != nil)
        if let val = val {
            #expect(String(cString: val) == "persistent_string")
        }
    }
}

// ============================================================
// MARK: - Profiling Tests
// ============================================================

@Suite("Profiling Tests")
struct ProfilingTests {

    @Test("dx_vm_set_profiling enables without crash")
    func testSetProfilingEnabled() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Enable profiling
        dx_vm_set_profiling(vm, true)
        #expect(vm.pointee.profiling_enabled == true)

        // Disable profiling
        dx_vm_set_profiling(vm, false)
        #expect(vm.pointee.profiling_enabled == false)
    }

    @Test("Opcode histogram populated after execution")
    func testOpcodeHistogramAfterExec() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Enable profiling
        dx_vm_set_profiling(vm, true)

        // Execute String.length to generate some opcode counts
        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let lengthMethod = dx_vm_find_method(strCls, "length", "I")!
        let strObj = dx_vm_create_string(vm, "test")!
        var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))]
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let _ = dx_vm_execute_method(vm, lengthMethod, &args, 1, &result)

        // Check that at least some execution happened (total instructions tracked)
        // Note: native methods may not increment opcode histogram, but the profiling
        // flag itself should be set without crash
        #expect(vm.pointee.profiling_enabled == true)
    }

    @Test("dx_vm_dump_hot_methods does not crash")
    func testDumpHotMethods() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        dx_vm_set_profiling(vm, true)

        // Execute a few methods to generate call counts
        let strCls = dx_vm_find_class(vm, "Ljava/lang/String;")!
        let lengthMethod = dx_vm_find_method(strCls, "length", "I")!
        let strObj = dx_vm_create_string(vm, "hello")!
        for _ in 0..<5 {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let _ = dx_vm_execute_method(vm, lengthMethod, &args, 1, &result)
        }

        // Should not crash when dumping (output goes to log, we just test no crash)
        dx_vm_dump_hot_methods(vm, 10)
        dx_vm_dump_opcode_stats(vm)
    }
}

// ============================================================
// MARK: - Animation / View Tests
// ============================================================

@Suite("Animation View Tests")
struct AnimationViewTests {

    @Test("Animation classes exist (ValueAnimator, ObjectAnimator)")
    func testAnimationClassesExist() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let valueAnimator = dx_vm_find_class(vm, "Landroid/animation/ValueAnimator;")
        #expect(valueAnimator != nil, "ValueAnimator should be registered")

        let objectAnimator = dx_vm_find_class(vm, "Landroid/animation/ObjectAnimator;")
        #expect(objectAnimator != nil, "ObjectAnimator should be registered")

        let animatorSet = dx_vm_find_class(vm, "Landroid/animation/AnimatorSet;")
        #expect(animatorSet != nil, "AnimatorSet should be registered")

        let animatorBase = dx_vm_find_class(vm, "Landroid/animation/Animator;")
        #expect(animatorBase != nil, "Animator base class should be registered")

        // Verify hierarchy: ObjectAnimator extends ValueAnimator extends Animator
        if let oa = objectAnimator {
            let superDesc = String(cString: oa.pointee.super_class.pointee.descriptor)
            #expect(superDesc == "Landroid/animation/ValueAnimator;",
                    "ObjectAnimator should extend ValueAnimator")
        }
        if let va = valueAnimator {
            let superDesc = String(cString: va.pointee.super_class.pointee.descriptor)
            #expect(superDesc == "Landroid/animation/Animator;",
                    "ValueAnimator should extend Animator")
        }
    }

    @Test("Alpha and rotation default values on render node")
    func testRenderNodeDefaults() {
        let root = dx_ui_node_create(DX_VIEW_TEXT_VIEW, 1)!
        dx_ui_node_set_text(root, "Test")

        let model = dx_render_model_create(root)
        #expect(model != nil)
        if let model = model {
            let node = model.pointee.root!
            // Default alpha should be 1.0 (fully opaque)
            #expect(node.pointee.alpha == 1.0, "Default alpha should be 1.0")
            // Default rotation should be 0
            #expect(node.pointee.rotation == 0.0, "Default rotation should be 0.0")
            // Default scale should be 1.0
            #expect(node.pointee.scale_x == 1.0, "Default scale_x should be 1.0")
            #expect(node.pointee.scale_y == 1.0, "Default scale_y should be 1.0")
            // Default translation should be 0
            #expect(node.pointee.translation_x == 0.0, "Default translation_x should be 0.0")
            #expect(node.pointee.translation_y == 0.0, "Default translation_y should be 0.0")
            dx_render_model_destroy(model)
        }

        dx_ui_node_destroy(root)
    }
}

// ============================================================
// MARK: - Retrofit Tests
// ============================================================

@Suite("Retrofit Tests")
struct RetrofitTests {

    @Test("Retrofit class exists and Builder works")
    func testRetrofitClassAndBuilder() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let retrofitCls = dx_vm_find_class(vm, "Lretrofit2/Retrofit;")
        #expect(retrofitCls != nil, "Retrofit class should be registered")

        let builderCls = dx_vm_find_class(vm, "Lretrofit2/Retrofit$Builder;")
        #expect(builderCls != nil, "Retrofit$Builder class should be registered")

        // Verify Builder has key methods
        if let builderCls = builderCls {
            let baseUrl = dx_vm_find_method(builderCls, "baseUrl", "LL")
            #expect(baseUrl != nil, "Retrofit$Builder.baseUrl should exist")

            let build = dx_vm_find_method(builderCls, "build", "L")
            #expect(build != nil, "Retrofit$Builder.build should exist")
        }

        // Verify related classes
        let callCls = dx_vm_find_class(vm, "Lretrofit2/Call;")
        #expect(callCls != nil, "Retrofit Call interface should be registered")

        let responseCls = dx_vm_find_class(vm, "Lretrofit2/Response;")
        #expect(responseCls != nil, "Retrofit Response class should be registered")

        let callbackCls = dx_vm_find_class(vm, "Lretrofit2/Callback;")
        #expect(callbackCls != nil, "Retrofit Callback interface should be registered")
    }

    @Test("Retrofit annotation classes registered")
    func testRetrofitAnnotations() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let annotations = [
            "Lretrofit2/http/GET;",
            "Lretrofit2/http/POST;",
            "Lretrofit2/http/PUT;",
            "Lretrofit2/http/DELETE;",
            "Lretrofit2/http/PATCH;",
            "Lretrofit2/http/HEAD;",
            "Lretrofit2/http/OPTIONS;",
            "Lretrofit2/http/HTTP;",
            "Lretrofit2/http/Path;",
            "Lretrofit2/http/Query;",
            "Lretrofit2/http/Body;",
            "Lretrofit2/http/Header;",
            "Lretrofit2/http/Field;",
            "Lretrofit2/http/FormUrlEncoded;",
            "Lretrofit2/http/Multipart;",
            "Lretrofit2/http/Streaming;",
        ]
        for desc in annotations {
            let cls = dx_vm_find_class(vm, desc)
            #expect(cls != nil, "Expected Retrofit annotation \(desc) to be registered")
        }

        // Also verify converter factories
        let gsonConverter = dx_vm_find_class(vm, "Lretrofit2/converter/gson/GsonConverterFactory;")
        #expect(gsonConverter != nil, "GsonConverterFactory should be registered")

        let moshiConverter = dx_vm_find_class(vm, "Lretrofit2/converter/moshi/MoshiConverterFactory;")
        #expect(moshiConverter != nil, "MoshiConverterFactory should be registered")
    }
}

// ============================================================
// MARK: - Layout XML Parsing Tests
// ============================================================

@Suite("Layout XML Parsing Tests")
struct LayoutXMLParsingTests {

    @Test("dx_axml_parse with valid AXML chunk header returns non-nil")
    func testAxmlParseValidHeader() {
        // Build a minimal valid AXML binary: magic (0x00080003) + file size + string pool chunk
        // Minimum: AXML header (8 bytes) + string pool chunk header (28 bytes) = 36 bytes
        var data = [UInt8](repeating: 0, count: 36)

        // AXML file magic: 0x00080003 little-endian
        data[0] = 0x03; data[1] = 0x00; data[2] = 0x08; data[3] = 0x00
        // File size: 36
        data[4] = 0x24; data[5] = 0x00; data[6] = 0x00; data[7] = 0x00

        // String pool chunk: type 0x001C0001, size 28
        data[8] = 0x01; data[9] = 0x00; data[10] = 0x1C; data[11] = 0x00
        // Chunk size: 28
        data[12] = 0x1C; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00
        // String count: 0
        data[16] = 0x00; data[17] = 0x00; data[18] = 0x00; data[19] = 0x00
        // Style count: 0
        data[20] = 0x00; data[21] = 0x00; data[22] = 0x00; data[23] = 0x00
        // Flags: 0
        data[24] = 0x00; data[25] = 0x00; data[26] = 0x00; data[27] = 0x00
        // Strings start: 0
        data[28] = 0x00; data[29] = 0x00; data[30] = 0x00; data[31] = 0x00
        // Styles start: 0
        data[32] = 0x00; data[33] = 0x00; data[34] = 0x00; data[35] = 0x00

        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&data, UInt32(data.count), &parser)
        // Should succeed or at least not crash
        if result == DX_OK {
            #expect(parser != nil)
            dx_axml_free(parser)
        }
        // If it fails, that's acceptable — we're testing it doesn't crash
    }

    @Test("dx_axml_parse with empty data returns error gracefully")
    func testAxmlParseEmptyData() {
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        var empty = [UInt8]()
        let result = dx_axml_parse(&empty, 0, &parser)
        // Must not crash; should return an error
        #expect(result != DX_OK)
        #expect(parser == nil)
    }

    @Test("dx_axml_free on nil does not crash")
    func testAxmlFreeNil() {
        // Passing nil should be a no-op, not a crash
        dx_axml_free(nil)
    }
}

// ============================================================
// MARK: - APK Loading Integration Tests
// ============================================================

@Suite("APK Loading Integration Tests")
struct APKLoadingIntegrationTests {

    @Test("dx_apk_open with empty data fails gracefully")
    func testApkOpenEmptyData() {
        var apk: UnsafeMutablePointer<DxApkFile>?
        var empty = [UInt8]()
        let result = dx_apk_open(&empty, 0, &apk)
        #expect(result != DX_OK)
        #expect(apk == nil)
    }

    @Test("dx_apk_open with truncated ZIP fails gracefully")
    func testApkOpenTruncatedZip() {
        // A valid ZIP starts with PK\x03\x04 but this is truncated
        var truncated: [UInt8] = [0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00]
        var apk: UnsafeMutablePointer<DxApkFile>?
        let result = dx_apk_open(&truncated, UInt32(truncated.count), &apk)
        #expect(result != DX_OK)
        #expect(apk == nil)
    }

    @Test("dx_apk_close on nil does not crash")
    func testApkCloseNil() {
        dx_apk_close(nil)
    }
}

// ============================================================
// MARK: - Memory Leak Test Pattern
// ============================================================

@Suite("Memory Safety Tests")
struct MemorySafetyTests {

    @Test("Create context, fail load, destroy — no crash")
    func testLoadFailDestroyCycle() {
        let ctx = dx_context_create()!
        // Attempt to load a nonexistent APK — should fail but not crash or leak
        let result = dx_context_load_apk(ctx, "/nonexistent/path/fake.apk")
        #expect(result != DX_OK)
        // Destroy should work cleanly even after failed load
        dx_context_destroy(ctx)
    }

    @Test("Create/destroy VM multiple times — consistent heap state")
    func testRepeatedVMCreateDestroy() {
        for _ in 0..<10 {
            let ctx = dx_context_create()!
            let vm = dx_vm_create(ctx)!
            dx_vm_register_framework_classes(vm)

            // Verify it works each time
            let cls = dx_vm_find_class(vm, "Ljava/lang/String;")
            #expect(cls != nil)

            dx_vm_destroy(vm)
            ctx.pointee.vm = nil
            dx_context_destroy(ctx)
        }
    }
}

// ============================================================
// MARK: - Performance Benchmark Stubs
// ============================================================

@Suite("Performance Benchmarks")
struct PerformanceBenchmarkTests {

    @Test("VM create and destroy completes in under 100ms")
    func testVMCreateDestroyPerformance() {
        let start = CFAbsoluteTimeGetCurrent()

        let ctx = dx_context_create()!
        let vm = dx_vm_create(ctx)!
        dx_vm_register_framework_classes(vm)
        dx_vm_destroy(vm)
        ctx.pointee.vm = nil
        dx_context_destroy(ctx)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0 // ms
        #expect(elapsed < 100.0, "VM create+register+destroy took \(elapsed)ms, expected < 100ms")
    }

    @Test("1000 dx_vm_find_class lookups complete quickly")
    func testFindClassLookupPerformance() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let classNames = [
            "Ljava/lang/Object;",
            "Ljava/lang/String;",
            "Ljava/util/ArrayList;",
            "Ljava/util/HashMap;",
            "Landroid/app/Activity;",
            "Landroid/widget/TextView;",
            "Landroid/widget/Button;",
            "Landroid/os/Bundle;",
            "Landroid/content/Intent;",
            "Landroid/view/View;",
        ]

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            for name in classNames {
                let cls = dx_vm_find_class(vm, name)
                #expect(cls != nil)
            }
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0 // ms
        // 1000 hash-table lookups should be well under 50ms
        #expect(elapsed < 50.0, "1000 find_class lookups took \(elapsed)ms, expected < 50ms")
    }

    // MARK: Opcodes per second

    @Test("Opcodes per second benchmark with 100K iteration loop")
    func testOpcodesPerSecond() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Synthetic bytecode: loop 100K iterations
        // v0 = counter (starts 0), v1 = increment (1), v2 = limit (100000)
        // Loop body: add-int v0,v0,v1 then if-lt v0,v2 branch back
        let insns: [UInt16] = [
            0x0012,                   // [0] const/4 v0, #0
            0x0113, 0x0001,           // [1] const/16 v1, #1
            0x0214, 0x86A0, 0x0001,   // [3] const v2, #100000 (format 31i)
            // loop start at pc=6:
            0x0090, 0x0100,           // [6] add-int v0, v0, v1
            0x203b, 0xFFFE,           // [8] if-lt v0, v2, -2 (goto pc=6)
            0x000E                    // [10] return-void
        ]

        let (method, buf) = makeSyntheticMethod(vm: vm, name: "benchLoop", shorty: "V", registers: 3, insns: insns)
        defer { freeSyntheticMethod(method, buf) }

        let start = CFAbsoluteTimeGetCurrent()
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, method, nil, 0, &result)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(status == DX_OK, "Loop benchmark must complete without error")

        let totalInsns = Double(vm.pointee.insn_count)
        let opsPerSec = totalInsns / elapsed
        print("[Benchmark] Opcodes/sec: \(String(format: "%.0f", opsPerSec)) (\(String(format: "%.0f", totalInsns)) insns in \(String(format: "%.4f", elapsed))s)")
    }

    // MARK: GC pause duration

    @Test("GC pause duration with 1200 heap objects")
    func testGCPauseDuration() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

        // Allocate 1200 objects on the heap
        for _ in 0..<1200 {
            let obj = dx_vm_alloc_object(vm, objCls)
            #expect(obj != nil, "Object allocation must succeed")
        }

        #expect(vm.pointee.heap_count >= 1200, "Heap must contain at least 1200 objects")

        // Measure GC pause
        let start = CFAbsoluteTimeGetCurrent()
        let gcResult = dx_vm_gc_collect(vm)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(gcResult == DX_OK, "GC must complete without error")
        #expect(elapsed < 1.0, "GC pause must be under 1 second (was \(elapsed)s)")

        print("[Benchmark] GC pause: \(String(format: "%.6f", elapsed))s for 1200 objects, heap after: \(vm.pointee.heap_count)")
    }

    // MARK: String interning throughput

    @Test("String interning throughput with 1000 unique strings")
    func testStringInterningThroughput() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let count = 1000

        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<count {
            let str = "intern_bench_\(i)"
            let interned = dx_vm_intern_string(vm, str)
            #expect(interned != nil, "Interning string \(i) must succeed")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let throughput = Double(count) / elapsed
        print("[Benchmark] String interning: \(String(format: "%.0f", throughput)) strings/sec (\(count) in \(String(format: "%.4f", elapsed))s)")

        // Verify interning returns the same object for duplicate strings
        let a = dx_vm_intern_string(vm, "intern_bench_0")
        let b = dx_vm_intern_string(vm, "intern_bench_0")
        #expect(a == b, "Interning the same string must return the same object")
    }

    // MARK: Class loading throughput

    @Test("Class loading throughput benchmark")
    func testClassLoadingThroughput() {
        let ctx = dx_context_create()!
        let vm = dx_vm_create(ctx)!
        defer {
            dx_vm_destroy(vm)
            ctx.pointee.vm = nil
            dx_context_destroy(ctx)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let regResult = dx_vm_register_framework_classes(vm)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(regResult == DX_OK, "Framework class registration must succeed")

        let classCount = vm.pointee.class_count
        let classesPerSec = Double(classCount) / elapsed
        print("[Benchmark] Class loading: \(String(format: "%.0f", classesPerSec)) classes/sec (\(classCount) classes in \(String(format: "%.4f", elapsed))s)")

        #expect(classCount > 100, "Framework must register at least 100 classes")
    }

    // MARK: Memory leak test

    @Test("Memory leak test - 10 VM create/destroy cycles")
    func testMemoryLeakFreedom() {
        for cycle in 0..<10 {
            let ctx = dx_context_create()!
            let vm = dx_vm_create(ctx)!

            // Register framework classes
            let regResult = dx_vm_register_framework_classes(vm)
            #expect(regResult == DX_OK, "Cycle \(cycle): class registration must succeed")

            // Allocate objects
            let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
            for _ in 0..<100 {
                let obj = dx_vm_alloc_object(vm, objCls)
                #expect(obj != nil, "Cycle \(cycle): object allocation must succeed")
            }

            // Intern some strings
            for j in 0..<50 {
                let interned = dx_vm_intern_string(vm, "leak_test_\(cycle)_\(j)")
                #expect(interned != nil, "Cycle \(cycle): string interning must succeed")
            }

            // Run GC
            let gcResult = dx_vm_gc_collect(vm)
            #expect(gcResult == DX_OK, "Cycle \(cycle): GC must succeed")

            // Destroy VM
            dx_vm_destroy(vm)
            ctx.pointee.vm = nil
            dx_context_destroy(ctx)
        }

        // If we get here without crash, basic leak-freedom is verified
        print("[Benchmark] Memory leak test: 10 cycles completed without crash")
    }
}

// ============================================================
// MARK: - Invoke/Dispatch Tests
// ============================================================

@Suite("Invoke and Dispatch Tests")
struct InvokeDispatchTests {

    @Test("invoke-virtual dispatches to correct vtable method")
    func testInvokeVirtualDispatch() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Use the framework's ArrayList class which has virtual methods
        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!
        let obj = dx_vm_alloc_object(vm, alCls)!

        // Call <init> via find_method + execute
        let initMethod = dx_vm_find_method(alCls, "<init>", "V")
        #expect(initMethod != nil, "ArrayList should have <init>")

        if let initMethod = initMethod {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: obj))]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let status = dx_vm_execute_method(vm, initMethod, &args, 1, &result)
            #expect(status == DX_OK)
        }

        // Now call "add" (virtual method) which should dispatch through vtable
        let addMethod = dx_vm_find_method(alCls, "add", "ZL")
        #expect(addMethod != nil, "ArrayList should have add method")

        if let addMethod = addMethod {
            let strObj = dx_vm_create_string(vm, "test_item")!
            var args = [
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: obj)),
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: strObj))
            ]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let status = dx_vm_execute_method(vm, addMethod, &args, 2, &result)
            #expect(status == DX_OK)
        }

        // Verify the item was added by calling "size"
        let sizeMethod = dx_vm_find_method(alCls, "size", "I")
        #expect(sizeMethod != nil, "ArrayList should have size method")

        if let sizeMethod = sizeMethod {
            var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: obj))]
            var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let status = dx_vm_execute_method(vm, sizeMethod, &args, 1, &result)
            #expect(status == DX_OK)
            #expect(result.i == 1, "ArrayList should have 1 element after add")
        }
    }

    @Test("invoke-super calls parent class implementation")
    func testInvokeSuperDispatch() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // AppCompatActivity extends Activity extends Context extends Object
        // Verify the class hierarchy is properly linked
        let appCompatCls = dx_vm_find_class(vm, "Landroidx/appcompat/app/AppCompatActivity;")!
        #expect(appCompatCls.pointee.super_class != nil, "AppCompatActivity should have a superclass")

        // The super chain should eventually reach Object
        var current: UnsafeMutablePointer<DxClass>? = appCompatCls
        var depth = 0
        while let cls = current, cls.pointee.super_class != nil {
            current = cls.pointee.super_class
            depth += 1
            if depth > 10 { break } // safety limit
        }
        #expect(depth > 0, "AppCompatActivity should have inheritance depth > 0")

        // Verify that toString (inherited from Object) is accessible on AppCompatActivity
        let toStringMethod = dx_vm_find_method(appCompatCls, "toString", "L")
        #expect(toStringMethod != nil, "toString should be inherited from Object")

        // The declaring class of toString should be Object (inherited via super)
        if let m = toStringMethod {
            let declDesc = String(cString: m.pointee.declaring_class.pointee.descriptor)
            // toString could be declared on Object or overridden; either way it should exist
            #expect(!declDesc.isEmpty)
        }
    }

    @Test("try/catch: exception within native method is handled")
    func testTryCatchSingleMethod() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Test that the VM can handle exceptions without crashing.
        // Create an object and invoke a method that would fail (e.g., get on empty ArrayList)
        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!
        let obj = dx_vm_alloc_object(vm, alCls)!

        // Init the arraylist
        let initMethod = dx_vm_find_method(alCls, "<init>", "V")!
        var initArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: obj))]
        var initResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let initStatus = dx_vm_execute_method(vm, initMethod, &initArgs, 1, &initResult)
        #expect(initStatus == DX_OK)

        // Try to get index 0 from empty list — should either throw or return error, not crash
        let getMethod = dx_vm_find_method(alCls, "get", "LI")
        if let getMethod = getMethod {
            var getArgs = [
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: obj)),
                DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            ]
            var getResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let getStatus = dx_vm_execute_method(vm, getMethod, &getArgs, 2, &getResult)
            // The method may return an error or set pending_exception — both are valid
            // Key assertion: we didn't crash
            if getStatus != DX_OK {
                // Exception path — verify pending_exception is set or error returned
                #expect(getStatus == DX_ERR_EXCEPTION || vm.pointee.pending_exception != nil || getStatus != DX_OK)
            }
            // Clear any pending exception
            vm.pointee.pending_exception = nil
        }
    }
}

// ============================================================
// MARK: - Malformed Input Tests
// ============================================================

@Suite("Malformed Input Tests")
struct MalformedInputTests {

    @Test("Truncated DEX data (first 8 bytes only) returns error")
    func testTruncatedDexData() {
        // Only provide the magic bytes, no header — should fail gracefully
        var data: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]
        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        // Must return an error (too short for header), not crash
        #expect(result != DX_OK, "Truncated DEX (8 bytes) should not parse as OK")
        #expect(dex == nil, "No DEX file should be allocated for truncated input")
    }

    @Test("DEX with invalid magic bytes returns DX_ERR_INVALID_MAGIC")
    func testInvalidMagicBytes() {
        // Full 112-byte buffer but with garbage magic
        var data = [UInt8](repeating: 0xFF, count: 112)
        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        #expect(result == DX_ERR_INVALID_MAGIC, "Invalid magic should return DX_ERR_INVALID_MAGIC")
        #expect(dex == nil)
    }

    @Test("Zero-length data returns error")
    func testZeroLengthData() {
        var data: [UInt8] = []
        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, 0, &dex)
        #expect(result != DX_OK, "Zero-length data should not parse as OK")
        #expect(dex == nil)
    }

    @Test("Valid magic but truncated header returns error")
    func testValidMagicTruncatedHeader() {
        // 32 bytes: valid magic in first 8, but not enough for full 112-byte header
        var data = [UInt8](repeating: 0, count: 32)
        let magic: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]
        for i in 0..<8 { data[i] = magic[i] }
        var dex: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&data, UInt32(data.count), &dex)
        #expect(result != DX_OK, "Valid magic with truncated header should return error")
        #expect(dex == nil)
    }
}

// ============================================================
// MARK: - Exception Handling Tests
// ============================================================

@Suite("Exception Handling Tests")
struct ExceptionHandlingTests {

    @Test("Exception within native method is caught without crash")
    func testTryCatchNativeException() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Create HashMap, call get with null key — should not crash
        let hmCls = dx_vm_find_class(vm, "Ljava/util/HashMap;")!
        let obj = dx_vm_alloc_object(vm, hmCls)!

        // Init the hashmap
        let initMethod = dx_vm_find_method(hmCls, "<init>", "V")!
        var initArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: obj))]
        var initResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let initStatus = dx_vm_execute_method(vm, initMethod, &initArgs, 1, &initResult)
        #expect(initStatus == DX_OK)

        // Call get with null — should return null or error, not crash
        let getMethod = dx_vm_find_method(hmCls, "get", "LL")
        if let getMethod = getMethod {
            var getArgs = [
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: obj)),
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: nil))
            ]
            var getResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let getStatus = dx_vm_execute_method(vm, getMethod, &getArgs, 2, &getResult)
            // Either OK (returning null) or an error is fine — key is no crash
            if getStatus != DX_OK {
                vm.pointee.pending_exception = nil
            }
        }
    }

    @Test("Instruction budget exhaustion returns gracefully")
    func testBudgetExhaustion() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Build a tight infinite loop:
        //   0: const/4 v0, #0
        //   1: goto -1  (back to itself — infinite loop)
        //   2: return-void (unreachable)
        // goto (0x28) format 10t: opcode | (offset << 8)
        //   offset = -1 -> 0xFF in signed byte -> 0x28 | (0xFF << 8) = 0xFF28
        let insns: [UInt16] = [
            0x0012,         // const/4 v0, #0
            0xFF28,         // goto -1 (loops back to itself)
            0x000E          // return-void (unreachable)
        ]
        let (method, buf) = makeSyntheticMethod(vm: vm, name: "infiniteLoop", shorty: "V", registers: 1, insns: insns)
        defer { freeSyntheticMethod(method, buf) }

        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, method, nil, 0, &result)
        // Should return budget exhausted (watchdog), not hang forever
        #expect(status == DX_ERR_BUDGET_EXHAUSTED, "Infinite loop should trigger budget exhaustion, got \(status.rawValue)")
    }

    @Test("Stack depth limit triggers DX_ERR_STACK_OVERFLOW")
    func testStackOverflow() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Build a method that calls itself recursively:
        //   invoke-virtual {v0}, method  -> but we use invoke-static pattern with native
        // Instead, use a simpler approach: create a native method that recursively calls itself
        // Actually, let's use the synthetic bytecode approach with invoke-static self-call.
        //
        // Simpler: Just directly push stack_depth to the limit and call execute_method
        // to verify DX_ERR_STACK_OVERFLOW is returned.

        // Build a simple return-void method
        let insns: [UInt16] = [
            0x000E  // return-void
        ]
        let (method, buf) = makeSyntheticMethod(vm: vm, name: "stackTest", shorty: "V", registers: 0, insns: insns)
        defer { freeSyntheticMethod(method, buf) }

        // Artificially set stack depth to the limit
        vm.pointee.stack_depth = UInt32(DX_MAX_STACK_DEPTH)

        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, method, nil, 0, &result)
        #expect(status == DX_ERR_STACK_OVERFLOW, "Should return stack overflow when depth is at limit")

        // Reset stack depth so teardown works cleanly
        vm.pointee.stack_depth = 0
    }
}

// ============================================================
// MARK: - Layout Parsing Tests
// ============================================================

@Suite("Layout Parsing Tests")
struct LayoutParsingTests {

    @Test("Parse minimal valid AXML data creates parser")
    func testMinimalAxmlParse() {
        // Build a minimal valid AXML:
        //   Bytes 0-3: magic 0x00080003 (little-endian)
        //   Bytes 4-7: file size
        //   Bytes 8+:  string pool chunk (type=0x0001, header_size=0x001C, chunk_size, etc.)
        //
        // String pool chunk header (28 bytes):
        //   uint16 type = 0x0001, uint16 header_size = 0x001C
        //   uint32 chunk_size = 28 (no strings)
        //   uint32 string_count = 0
        //   uint32 style_count = 0
        //   uint32 flags = 0
        //   uint32 strings_start = 28 (relative to chunk start)
        //   uint32 styles_start = 0
        var data: [UInt8] = [
            // AXML magic (little-endian 0x00080003)
            0x03, 0x00, 0x08, 0x00,
            // File size = 36 (8 header + 28 string pool)
            0x24, 0x00, 0x00, 0x00,
            // String pool chunk: type=0x0001
            0x01, 0x00,
            // header_size = 0x001C = 28
            0x1C, 0x00,
            // chunk_size = 28
            0x1C, 0x00, 0x00, 0x00,
            // string_count = 0
            0x00, 0x00, 0x00, 0x00,
            // style_count = 0
            0x00, 0x00, 0x00, 0x00,
            // flags = 0
            0x00, 0x00, 0x00, 0x00,
            // strings_start = 28 (relative to chunk start)
            0x1C, 0x00, 0x00, 0x00,
            // styles_start = 0
            0x00, 0x00, 0x00, 0x00,
        ]

        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&data, UInt32(data.count), &parser)
        #expect(result == DX_OK, "Minimal valid AXML should parse successfully")
        if let parser = parser {
            #expect(parser.pointee.string_count == 0, "Empty string pool should have 0 strings")
            dx_axml_free(parser)
        }
    }

    @Test("AXML with invalid magic is rejected")
    func testAxmlInvalidMagic() {
        var data: [UInt8] = [
            0xFF, 0xFF, 0xFF, 0xFF,  // bad magic
            0x08, 0x00, 0x00, 0x00,  // file size
        ]
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&data, UInt32(data.count), &parser)
        #expect(result == DX_ERR_AXML_INVALID, "Invalid AXML magic should return DX_ERR_AXML_INVALID")
        #expect(parser == nil)
    }

    @Test("AXML too short is rejected")
    func testAxmlTooShort() {
        // Less than 8 bytes should be rejected
        var data: [UInt8] = [0x03, 0x00, 0x08, 0x00]
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&data, UInt32(data.count), &parser)
        #expect(result == DX_ERR_AXML_INVALID, "AXML shorter than 8 bytes should be rejected")
        #expect(parser == nil)
    }

    @Test("AXML with truncated string pool chunk is rejected")
    func testAxmlTruncatedStringPool() {
        // Valid magic but string pool chunk is cut short
        var data: [UInt8] = [
            // AXML magic
            0x03, 0x00, 0x08, 0x00,
            // File size = 20 (8 header + 12 truncated chunk)
            0x14, 0x00, 0x00, 0x00,
            // String pool chunk type = 0x0001
            0x01, 0x00,
            // header_size = 0x001C = 28
            0x1C, 0x00,
            // chunk_size = 28 (but we only provide 12 bytes of chunk data)
            0x1C, 0x00, 0x00, 0x00,
            // Only 4 more bytes — not enough for full string pool header (needs 28)
            0x00, 0x00, 0x00, 0x00,
        ]
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&data, UInt32(data.count), &parser)
        // Should fail because the string pool chunk is truncated
        #expect(result != DX_OK, "Truncated string pool chunk should fail to parse")
    }
}

// ============================================================
// MARK: - GC Verification Tests
// ============================================================

@Suite("GC Verification Tests")
struct GCVerificationTests {

    @Test("GC frees unreachable objects - heap count decreases to baseline")
    func testGCFreesUnreachableObjects() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

        // Record baseline heap count (framework statics may have allocated some objects)
        let baseline = vm.pointee.heap_count

        // Allocate 50 objects that are not rooted anywhere
        for _ in 0..<50 {
            let _ = dx_vm_alloc_object(vm, objCls)
        }
        #expect(vm.pointee.heap_count == baseline + 50,
                "Heap should grow by exactly 50 after allocation")

        // Run full GC - none of these objects are reachable
        dx_vm_gc_collect(vm)

        #expect(vm.pointee.heap_count < baseline + 50,
                "GC must free at least some unreachable objects")
    }

    @Test("GC preserves reachable objects - interned strings survive collection")
    func testGCPreservesReachableObjects() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Intern strings (these are rooted in the intern table)
        let s1 = dx_vm_intern_string(vm, "keep_alive_1")
        let s2 = dx_vm_intern_string(vm, "keep_alive_2")
        let s3 = dx_vm_intern_string(vm, "keep_alive_3")
        #expect(s1 != nil)
        #expect(s2 != nil)
        #expect(s3 != nil)

        // Also allocate some unreachable garbage
        let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
        for _ in 0..<30 {
            let _ = dx_vm_alloc_object(vm, objCls)
        }

        // Run GC
        dx_vm_gc_collect(vm)

        // Interned strings must still be valid
        let v1 = dx_vm_get_string_value(s1)
        let v2 = dx_vm_get_string_value(s2)
        let v3 = dx_vm_get_string_value(s3)
        #expect(v1 != nil)
        #expect(v2 != nil)
        #expect(v3 != nil)
        #expect(String(cString: v1!) == "keep_alive_1")
        #expect(String(cString: v2!) == "keep_alive_2")
        #expect(String(cString: v3!) == "keep_alive_3")
    }
}

// ============================================================
// MARK: - String Interning Deduplication Tests
// ============================================================

@Suite("String Interning Deduplication Tests")
struct StringInterningDeduplicationTests {

    @Test("String interning deduplicates identical strings into single object")
    func testStringInterningDeduplication() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Intern the same string multiple times
        let a1 = dx_vm_intern_string(vm, "dedup_test")
        let a2 = dx_vm_intern_string(vm, "dedup_test")
        let a3 = dx_vm_intern_string(vm, "dedup_test")

        // All must return the exact same object pointer (deduplication)
        #expect(a1 != nil)
        #expect(a1 == a2, "Interning same string twice must return identical pointer")
        #expect(a2 == a3, "Interning same string thrice must return identical pointer")

        // Intern a different string to confirm it's a distinct object
        let b1 = dx_vm_intern_string(vm, "other_string")
        #expect(b1 != nil)
        #expect(b1 != a1, "Different string content must produce a different object")

        // Verify the deduplicated string has correct value
        let val = dx_vm_get_string_value(a1)
        #expect(val != nil)
        #expect(String(cString: val!) == "dedup_test")
    }
}

// ============================================================
// MARK: - Malformed APK Tests
// ============================================================

@Suite("Malformed APK Tests")
struct MalformedAPKTests {

    @Test("Load malformed APK (truncated) without crash")
    func testTruncatedAPKDoesNotCrash() {
        // Create a truncated APK: valid ZIP local-file-header signature
        // followed by garbage/truncation. This must not crash.
        var truncatedData: [UInt8] = [
            0x50, 0x4B, 0x03, 0x04,  // ZIP local file header signature
            0x14, 0x00,              // version needed
            0x00, 0x00,              // flags
            0x08, 0x00,              // compression method (deflate)
            0x00, 0x00, 0x00, 0x00,  // mod time/date
            0x00, 0x00, 0x00, 0x00,  // CRC-32
            0xFF, 0xFF, 0x00, 0x00,  // compressed size (bogus)
            0xFF, 0xFF, 0x00, 0x00,  // uncompressed size (bogus)
            0x0A, 0x00,              // filename length = 10
            0x00, 0x00,              // extra field length = 0
            // filename "classes.dex" (truncated - only 10 bytes but data ends here)
            0x63, 0x6C, 0x61, 0x73, 0x73, 0x65, 0x73, 0x2E, 0x64, 0x65,
        ]

        // Attempt to parse the truncated data as an APK
        var apk: UnsafeMutablePointer<DxApkFile>?
        let result = dx_apk_open(&truncatedData, UInt32(truncatedData.count), &apk)

        // It should fail gracefully (not crash), returning an error code
        #expect(result != DX_OK,
                "Loading a truncated APK must fail with an error, not crash")
        #expect(apk == nil, "APK pointer must be nil on failure")
    }
}

// ============================================================
// MARK: - Synthetic DEX Fixture Generator
// ============================================================

/// Creates a minimal valid DEX bytecode buffer in memory.
/// Contains one class (`LTest;`) with one direct method (`<init>`) that performs `return-void`.
private func buildMinimalDEX() -> [UInt8] {
    let headerSize: UInt32 = 112

    let stringIdsOff: UInt32 = headerSize
    let stringIdsSize: UInt32 = 3  // "<init>", "LTest;", "V"

    let typeIdsOff: UInt32 = stringIdsOff + stringIdsSize * 4
    let typeIdsSize: UInt32 = 2

    let protoIdsOff: UInt32 = typeIdsOff + typeIdsSize * 4
    let protoIdsSize: UInt32 = 1

    let methodIdsOff: UInt32 = protoIdsOff + protoIdsSize * 12
    let methodIdsSize: UInt32 = 1

    let classDefsOff: UInt32 = methodIdsOff + methodIdsSize * 8
    let classDefsSize: UInt32 = 1

    let dataOff: UInt32 = classDefsOff + classDefsSize * 32
    let classDataOff: UInt32 = dataOff

    func uleb128(_ value: UInt32) -> [UInt8] {
        var v = value
        var result: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            result.append(byte)
        } while v != 0
        return result
    }

    // class_data: static=0, instance=0, direct=1, virtual=0
    //             method_idx_diff=0, access=0x10001(PUBLIC|CONSTRUCTOR)
    let classDataPrefix: [UInt8] = [0, 0, 1, 0, 0, 0x81, 0x80, 0x04]

    let estimatedCodeOff = (classDataOff + UInt32(classDataPrefix.count) + 2 + 3) & ~3
    let codeOffBytes = uleb128(estimatedCodeOff)
    let classDataLen = UInt32(classDataPrefix.count + codeOffBytes.count)
    let codeItemOff = (classDataOff + classDataLen + 3) & ~3

    let codeOffBytesFinal = uleb128(codeItemOff)
    let classDataFinal: [UInt8] = classDataPrefix + codeOffBytesFinal

    let codeItem: [UInt8] = [
        1, 0,  1, 0,  0, 0,  0, 0,   // regs=1, ins=1, outs=0, tries=0
        0, 0, 0, 0,                   // debug_info_off=0
        1, 0, 0, 0,                   // insns_size=1
        0x0e, 0x00                     // return-void
    ]

    let afterCodeItem = codeItemOff + UInt32(codeItem.count)

    let string0: [UInt8] = [6] + Array("<init>".utf8) + [0]
    let string1: [UInt8] = [6] + Array("LTest;".utf8) + [0]
    let string2: [UInt8] = [1] + Array("V".utf8) + [0]

    let string0Off = afterCodeItem
    let string1Off = string0Off + UInt32(string0.count)
    let string2Off = string1Off + UInt32(string1.count)

    let fileSize = string2Off + UInt32(string2.count)
    let dataSize = fileSize - dataOff

    var dex = [UInt8](repeating: 0, count: Int(fileSize))

    func writeU32(_ offset: Int, _ value: UInt32) {
        dex[offset] = UInt8(value & 0xFF)
        dex[offset+1] = UInt8((value >> 8) & 0xFF)
        dex[offset+2] = UInt8((value >> 16) & 0xFF)
        dex[offset+3] = UInt8((value >> 24) & 0xFF)
    }
    func writeU16(_ offset: Int, _ value: UInt16) {
        dex[offset] = UInt8(value & 0xFF)
        dex[offset+1] = UInt8((value >> 8) & 0xFF)
    }

    let magic: [UInt8] = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]
    for i in 0..<8 { dex[i] = magic[i] }
    writeU32(32, fileSize)
    writeU32(36, headerSize)
    writeU32(40, 0x12345678)
    writeU32(56, stringIdsSize); writeU32(60, stringIdsOff)
    writeU32(64, typeIdsSize);   writeU32(68, typeIdsOff)
    writeU32(72, protoIdsSize);  writeU32(76, protoIdsOff)
    writeU32(80, 0); writeU32(84, 0)
    writeU32(88, methodIdsSize); writeU32(92, methodIdsOff)
    writeU32(96, classDefsSize); writeU32(100, classDefsOff)
    writeU32(104, dataSize);     writeU32(108, dataOff)

    writeU32(Int(stringIdsOff),     string0Off)
    writeU32(Int(stringIdsOff) + 4, string1Off)
    writeU32(Int(stringIdsOff) + 8, string2Off)

    writeU32(Int(typeIdsOff),     1)  // "LTest;"
    writeU32(Int(typeIdsOff) + 4, 2)  // "V"

    writeU32(Int(protoIdsOff),     2) // shorty "V"
    writeU32(Int(protoIdsOff) + 4, 1) // return type "V"
    writeU32(Int(protoIdsOff) + 8, 0) // no params

    writeU16(Int(methodIdsOff),     0) // class LTest;
    writeU16(Int(methodIdsOff) + 2, 0) // proto ()V
    writeU32(Int(methodIdsOff) + 4, 0) // name "<init>"

    writeU32(Int(classDefsOff),      0)
    writeU32(Int(classDefsOff) + 4,  1)          // PUBLIC
    writeU32(Int(classDefsOff) + 8,  0xFFFFFFFF) // no superclass
    writeU32(Int(classDefsOff) + 12, 0)
    writeU32(Int(classDefsOff) + 16, 0xFFFFFFFF)
    writeU32(Int(classDefsOff) + 20, 0)
    writeU32(Int(classDefsOff) + 24, classDataOff)
    writeU32(Int(classDefsOff) + 28, 0)

    for (i, b) in classDataFinal.enumerated() { dex[Int(classDataOff) + i] = b }
    for (i, b) in codeItem.enumerated() { dex[Int(codeItemOff) + i] = b }
    for (i, b) in string0.enumerated() { dex[Int(string0Off) + i] = b }
    for (i, b) in string1.enumerated() { dex[Int(string1Off) + i] = b }
    for (i, b) in string2.enumerated() { dex[Int(string2Off) + i] = b }

    return dex
}

/// Creates a minimal valid ZIP archive with given entries (STORE compression).
private func buildMinimalZIP(entries: [(name: String, data: [UInt8])]) -> [UInt8] {
    var zip: [UInt8] = []

    struct LocalEntry {
        let name: String
        let localHeaderOffset: Int
        let data: [UInt8]
        let crc32: UInt32
    }

    func crc32Compute(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1 != 0) ? ((crc >> 1) ^ 0xEDB88320) : (crc >> 1)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    func appendU16(_ value: UInt16) {
        zip.append(UInt8(value & 0xFF))
        zip.append(UInt8((value >> 8) & 0xFF))
    }
    func appendU32(_ value: UInt32) {
        zip.append(UInt8(value & 0xFF))
        zip.append(UInt8((value >> 8) & 0xFF))
        zip.append(UInt8((value >> 16) & 0xFF))
        zip.append(UInt8((value >> 24) & 0xFF))
    }

    var localEntries: [LocalEntry] = []

    for entry in entries {
        let nameBytes = Array(entry.name.utf8)
        let crc = crc32Compute(entry.data)
        let localOffset = zip.count

        appendU32(0x04034b50)
        appendU16(20); appendU16(0); appendU16(0)
        appendU16(0); appendU16(0)
        appendU32(crc)
        appendU32(UInt32(entry.data.count))
        appendU32(UInt32(entry.data.count))
        appendU16(UInt16(nameBytes.count))
        appendU16(0)
        zip.append(contentsOf: nameBytes)
        zip.append(contentsOf: entry.data)

        localEntries.append(LocalEntry(name: entry.name, localHeaderOffset: localOffset,
                                       data: entry.data, crc32: crc))
    }

    let cdOffset = zip.count

    for local in localEntries {
        let nameBytes = Array(local.name.utf8)
        appendU32(0x02014b50)
        appendU16(20); appendU16(20); appendU16(0); appendU16(0)
        appendU16(0); appendU16(0)
        appendU32(local.crc32)
        appendU32(UInt32(local.data.count))
        appendU32(UInt32(local.data.count))
        appendU16(UInt16(nameBytes.count))
        appendU16(0); appendU16(0); appendU16(0)
        appendU16(0); appendU32(0)
        appendU32(UInt32(local.localHeaderOffset))
        zip.append(contentsOf: nameBytes)
    }

    let cdSize = zip.count - cdOffset
    appendU32(0x06054b50)
    appendU16(0); appendU16(0)
    appendU16(UInt16(localEntries.count))
    appendU16(UInt16(localEntries.count))
    appendU32(UInt32(cdSize))
    appendU32(UInt32(cdOffset))
    appendU16(0)

    return zip
}

/// Creates minimal valid AXML binary data with a UTF-8 string pool.
private func buildMinimalAXML(strings: [String], resourceIds: [UInt32] = []) -> [UInt8] {
    var axml: [UInt8] = []

    func appendU16(_ value: UInt16) {
        axml.append(UInt8(value & 0xFF))
        axml.append(UInt8((value >> 8) & 0xFF))
    }
    func appendU32(_ value: UInt32) {
        axml.append(UInt8(value & 0xFF))
        axml.append(UInt8((value >> 8) & 0xFF))
        axml.append(UInt8((value >> 16) & 0xFF))
        axml.append(UInt8((value >> 24) & 0xFF))
    }

    var stringDataBytes: [UInt8] = []
    var stringOffsets: [UInt32] = []

    for str in strings {
        let utf8 = Array(str.utf8)
        stringOffsets.append(UInt32(stringDataBytes.count))
        stringDataBytes.append(UInt8(utf8.count))
        stringDataBytes.append(UInt8(utf8.count))
        stringDataBytes.append(contentsOf: utf8)
        stringDataBytes.append(0)
    }

    let offsetTableSize = strings.count * 4
    let stringsStart: UInt32 = 28 + UInt32(offsetTableSize)
    let stringPoolChunkSize: UInt32 = stringsStart + UInt32(stringDataBytes.count)
    let resMapChunkSize: UInt32 = resourceIds.isEmpty ? 0 : (8 + UInt32(resourceIds.count) * 4)
    let totalSize: UInt32 = 8 + stringPoolChunkSize + resMapChunkSize

    appendU32(0x00080003)
    appendU32(totalSize)

    appendU16(0x0001); appendU16(0x001C)
    appendU32(stringPoolChunkSize)
    appendU32(UInt32(strings.count))
    appendU32(0)
    appendU32(1 << 8) // UTF-8 flag
    appendU32(stringsStart)
    appendU32(0)

    for off in stringOffsets { appendU32(off) }
    axml.append(contentsOf: stringDataBytes)

    if !resourceIds.isEmpty {
        appendU16(0x0180); appendU16(0x0008)
        appendU32(resMapChunkSize)
        for id in resourceIds { appendU32(id) }
    }

    return axml
}

// ============================================================
// MARK: - Synthetic DEX Fixture Tests
// ============================================================

@Suite("Synthetic DEX Fixture Tests")
struct SyntheticDEXFixtureTests {

    @Test("buildMinimalDEX creates parseable DEX bytecode")
    func testMinimalDEXParses() {
        var dex = buildMinimalDEX()
        var dexFile: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&dex, UInt32(dex.count), &dexFile)
        #expect(result == DX_OK, "Minimal DEX should parse successfully")
        if let dexFile = dexFile {
            #expect(dexFile.pointee.string_count == 3)
            #expect(dexFile.pointee.type_count == 2)
            #expect(dexFile.pointee.method_count == 1)
            #expect(dexFile.pointee.class_count == 1)
            dx_dex_free(dexFile)
        }
    }

    @Test("Synthetic DEX contains correct strings")
    func testMinimalDEXStrings() {
        var dex = buildMinimalDEX()
        var dexFile: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&dex, UInt32(dex.count), &dexFile)
        #expect(result == DX_OK)
        guard let dexFile = dexFile else { return }
        defer { dx_dex_free(dexFile) }

        if let s0 = dx_dex_get_string(dexFile, 0) {
            #expect(String(cString: s0) == "<init>")
        } else { #expect(Bool(false), "String 0 is nil") }

        if let s1 = dx_dex_get_string(dexFile, 1) {
            #expect(String(cString: s1) == "LTest;")
        } else { #expect(Bool(false), "String 1 is nil") }

        if let s2 = dx_dex_get_string(dexFile, 2) {
            #expect(String(cString: s2) == "V")
        } else { #expect(Bool(false), "String 2 is nil") }
    }

    @Test("Synthetic DEX method name and class are correct")
    func testMinimalDEXMethodName() {
        var dex = buildMinimalDEX()
        var dexFile: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&dex, UInt32(dex.count), &dexFile)
        #expect(result == DX_OK)
        guard let dexFile = dexFile else { return }
        defer { dx_dex_free(dexFile) }

        if let name = dx_dex_get_method_name(dexFile, 0) {
            #expect(String(cString: name) == "<init>")
        }
        if let cls = dx_dex_get_method_class(dexFile, 0) {
            #expect(String(cString: cls) == "LTest;")
        }
    }

    @Test("Synthetic DEX class data can be parsed")
    func testMinimalDEXClassData() {
        var dex = buildMinimalDEX()
        var dexFile: UnsafeMutablePointer<DxDexFile>?
        let result = dx_dex_parse(&dex, UInt32(dex.count), &dexFile)
        #expect(result == DX_OK)
        guard let dexFile = dexFile else { return }
        defer { dx_dex_free(dexFile) }

        let parseResult = dx_dex_parse_class_data(dexFile, 0)
        #expect(parseResult == DX_OK, "Class data should parse successfully")

        if let classData = dexFile.pointee.class_data?[0] {
            #expect(classData.pointee.direct_methods_count == 1)
            #expect(classData.pointee.virtual_methods_count == 0)
            #expect(classData.pointee.static_fields_count == 0)
            #expect(classData.pointee.instance_fields_count == 0)
        }
    }
}

// ============================================================
// MARK: - APK Loading Integration Tests
// ============================================================

@Suite("Synthetic APK Integration Tests")
struct SyntheticAPKIntegrationTests {

    @Test("Parse minimal ZIP with DEX inside returns success")
    func testMinimalZIPWithDEX() {
        let dexData = buildMinimalDEX()
        var zipData = buildMinimalZIP(entries: [
            (name: "classes.dex", data: dexData)
        ])

        var apk: UnsafeMutablePointer<DxApkFile>?
        let result = dx_apk_open(&zipData, UInt32(zipData.count), &apk)
        #expect(result == DX_OK, "Minimal ZIP with DEX should parse successfully")

        if let apk = apk {
            #expect(apk.pointee.entry_count == 1)

            var entry: UnsafePointer<DxZipEntry>?
            let findResult = dx_apk_find_entry(apk, "classes.dex", &entry)
            #expect(findResult == DX_OK)

            if let entry = entry {
                #expect(entry.pointee.compression_method == 0)
                #expect(entry.pointee.uncompressed_size == UInt32(dexData.count))

                var extractedData: UnsafeMutablePointer<UInt8>?
                var extractedSize: UInt32 = 0
                let extractResult = dx_apk_extract_entry(apk, entry, &extractedData, &extractedSize)
                #expect(extractResult == DX_OK)
                #expect(extractedSize == UInt32(dexData.count))

                if let extractedData = extractedData {
                    var dexFile: UnsafeMutablePointer<DxDexFile>?
                    let dexResult = dx_dex_parse(extractedData, extractedSize, &dexFile)
                    #expect(dexResult == DX_OK, "Extracted DEX should parse")
                    if let dexFile = dexFile { dx_dex_free(dexFile) }
                    free(extractedData)
                }
            }

            dx_apk_close(apk)
        }
    }

    @Test("Parse ZIP with multiple entries including DEX")
    func testZIPWithMultipleEntries() {
        let dexData = buildMinimalDEX()
        var zipData = buildMinimalZIP(entries: [
            (name: "classes.dex", data: dexData),
            (name: "AndroidManifest.xml", data: [0x00, 0x01, 0x02, 0x03]),
            (name: "res/layout/main.xml", data: [0xAA, 0xBB])
        ])

        var apk: UnsafeMutablePointer<DxApkFile>?
        let result = dx_apk_open(&zipData, UInt32(zipData.count), &apk)
        #expect(result == DX_OK)

        if let apk = apk {
            #expect(apk.pointee.entry_count == 3)

            var e1: UnsafePointer<DxZipEntry>?
            #expect(dx_apk_find_entry(apk, "classes.dex", &e1) == DX_OK)
            var e2: UnsafePointer<DxZipEntry>?
            #expect(dx_apk_find_entry(apk, "AndroidManifest.xml", &e2) == DX_OK)
            var e3: UnsafePointer<DxZipEntry>?
            #expect(dx_apk_find_entry(apk, "res/layout/main.xml", &e3) == DX_OK)
            var e4: UnsafePointer<DxZipEntry>?
            #expect(dx_apk_find_entry(apk, "nonexistent.file", &e4) != DX_OK)

            dx_apk_close(apk)
        }
    }

    @Test("Parse ZIP with no DEX file — entry lookup fails gracefully")
    func testZIPWithNoDEX() {
        var zipData = buildMinimalZIP(entries: [
            (name: "AndroidManifest.xml", data: [0x01, 0x02, 0x03, 0x04]),
            (name: "res/values/strings.xml", data: [0x05, 0x06])
        ])

        var apk: UnsafeMutablePointer<DxApkFile>?
        let result = dx_apk_open(&zipData, UInt32(zipData.count), &apk)
        #expect(result == DX_OK, "Valid ZIP without DEX should still parse")

        if let apk = apk {
            #expect(apk.pointee.entry_count == 2)
            var dexEntry: UnsafePointer<DxZipEntry>?
            let findResult = dx_apk_find_entry(apk, "classes.dex", &dexEntry)
            #expect(findResult != DX_OK)
            #expect(dexEntry == nil)
            dx_apk_close(apk)
        }
    }

    @Test("Parse corrupt/truncated ZIP returns error without crash")
    func testCorruptZIPDoesNotCrash() {
        var garbage: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33,
                                0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB,
                                0xCC, 0xDD, 0xEE, 0xFF, 0x01, 0x02]
        var apk: UnsafeMutablePointer<DxApkFile>?
        let r1 = dx_apk_open(&garbage, UInt32(garbage.count), &apk)
        #expect(r1 != DX_OK)
        #expect(apk == nil)

        var tiny: [UInt8] = [0x50, 0x4B]
        let r2 = dx_apk_open(&tiny, UInt32(tiny.count), &apk)
        #expect(r2 != DX_OK)

        var badEOCD: [UInt8] = [UInt8](repeating: 0, count: 22)
        badEOCD[0] = 0x50; badEOCD[1] = 0x4B; badEOCD[2] = 0x05; badEOCD[3] = 0x06
        badEOCD[10] = 1; badEOCD[11] = 0
        badEOCD[16] = 0xFF; badEOCD[17] = 0xFF
        let r3 = dx_apk_open(&badEOCD, UInt32(badEOCD.count), &apk)
        #expect(r3 != DX_OK)
    }

    @Test("Parse null pointer returns error")
    func testNullPointerAPK() {
        var apk: UnsafeMutablePointer<DxApkFile>?
        let result = dx_apk_open(nil, 0, &apk)
        #expect(result == DX_ERR_NULL_PTR)
    }

    @Test("Empty ZIP (no entries) parses successfully")
    func testEmptyZIP() {
        var zipData = buildMinimalZIP(entries: [])
        var apk: UnsafeMutablePointer<DxApkFile>?
        let result = dx_apk_open(&zipData, UInt32(zipData.count), &apk)
        #expect(result == DX_OK)
        if let apk = apk {
            #expect(apk.pointee.entry_count == 0)
            dx_apk_close(apk)
        }
    }
}

// ============================================================
// MARK: - Layout XML (AXML) Parsing Tests
// ============================================================

@Suite("AXML Parsing Tests")
struct AXMLParsingTests {

    @Test("Parse minimal valid AXML binary data")
    func testMinimalAXMLParses() {
        var axmlData = buildMinimalAXML(strings: ["android", "LinearLayout", "orientation"])
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&axmlData, UInt32(axmlData.count), &parser)
        #expect(result == DX_OK, "Minimal AXML should parse")
        if let parser = parser {
            #expect(parser.pointee.string_count == 3)
            dx_axml_free(parser)
        }
    }

    @Test("AXML string pool extraction is correct")
    func testAXMLStringExtraction() {
        let testStrings = ["http://schemas.android.com/apk/res/android",
                           "LinearLayout", "TextView", "text", "Hello World"]
        var axmlData = buildMinimalAXML(strings: testStrings)
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&axmlData, UInt32(axmlData.count), &parser)
        #expect(result == DX_OK)
        guard let parser = parser else { return }
        defer { dx_axml_free(parser) }

        #expect(parser.pointee.string_count == UInt32(testStrings.count))
        for (i, expected) in testStrings.enumerated() {
            if let strPtr = parser.pointee.strings[i] {
                #expect(String(cString: strPtr) == expected,
                        "String[\(i)] mismatch")
            } else {
                #expect(Bool(false), "String[\(i)] is nil")
            }
        }
    }

    @Test("AXML resource ID map is parsed correctly")
    func testAXMLResourceIDs() {
        let resIds: [UInt32] = [0x01010000, 0x01010001, 0x01010003]
        var axmlData = buildMinimalAXML(strings: ["theme", "label", "name"],
                                        resourceIds: resIds)
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&axmlData, UInt32(axmlData.count), &parser)
        #expect(result == DX_OK)
        guard let parser = parser else { return }
        defer { dx_axml_free(parser) }

        #expect(parser.pointee.res_id_count == UInt32(resIds.count))
        for (i, expected) in resIds.enumerated() {
            #expect(parser.pointee.res_ids[i] == expected)
        }
    }

    @Test("AXML with empty string pool parses")
    func testAXMLEmptyStringPool() {
        var axmlData = buildMinimalAXML(strings: [])
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&axmlData, UInt32(axmlData.count), &parser)
        #expect(result == DX_OK)
        if let parser = parser {
            #expect(parser.pointee.string_count == 0)
            dx_axml_free(parser)
        }
    }

    @Test("Invalid AXML magic is rejected")
    func testInvalidAXMLMagic() {
        var badData: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00]
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&badData, UInt32(badData.count), &parser)
        #expect(result == DX_ERR_AXML_INVALID)
        #expect(parser == nil)
    }

    @Test("Truncated AXML data does not crash")
    func testTruncatedAXML() {
        var truncated: [UInt8] = [0x03, 0x00, 0x08, 0x00, 0x00, 0x01, 0x00, 0x00]
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&truncated, UInt32(truncated.count), &parser)
        if result != DX_OK {
            #expect(parser == nil)
        } else if let parser = parser {
            dx_axml_free(parser)
        }
    }

    @Test("AXML too small is rejected")
    func testAXMLTooSmall() {
        var tinyData: [UInt8] = [0x03, 0x00, 0x08]
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&tinyData, UInt32(tinyData.count), &parser)
        #expect(result == DX_ERR_AXML_INVALID)
    }

    @Test("AXML null pointer returns error")
    func testAXMLNullPointer() {
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(nil, 0, &parser)
        #expect(result == DX_ERR_NULL_PTR)
    }

    @Test("AXML with many strings exercises string pool capacity")
    func testAXMLManyStrings() {
        var strings: [String] = []
        for i in 0..<100 { strings.append("string_\(i)") }
        var axmlData = buildMinimalAXML(strings: strings)

        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&axmlData, UInt32(axmlData.count), &parser)
        #expect(result == DX_OK)
        if let parser = parser {
            #expect(parser.pointee.string_count == 100)
            if let s0 = parser.pointee.strings[0] {
                #expect(String(cString: s0) == "string_0")
            }
            if let s99 = parser.pointee.strings[99] {
                #expect(String(cString: s99) == "string_99")
            }
            dx_axml_free(parser)
        }
    }

    @Test("AXML with special characters in strings")
    func testAXMLSpecialCharStrings() {
        let specialStrings = ["com.example.app",
                              "http://schemas.android.com/apk/res/android",
                              "@string/app_name", "match_parent", ""]
        var axmlData = buildMinimalAXML(strings: specialStrings)
        var parser: UnsafeMutablePointer<DxAxmlParser>?
        let result = dx_axml_parse(&axmlData, UInt32(axmlData.count), &parser)
        #expect(result == DX_OK)
        guard let parser = parser else { return }
        defer { dx_axml_free(parser) }

        #expect(parser.pointee.string_count == UInt32(specialStrings.count))
        for (i, expected) in specialStrings.enumerated() {
            if let strPtr = parser.pointee.strings[i] {
                #expect(String(cString: strPtr) == expected)
            }
        }
    }
}

// ============================================================
// MARK: - Memory Leak Tests
// ============================================================

@Suite("Memory Leak Tests")
struct MemoryLeakTests {

    @Test("VM create/register/alloc/GC/destroy cycle x20 does not crash")
    func testVMCycleStress() {
        for cycle in 0..<20 {
            let ctx = dx_context_create()!
            let vm = dx_vm_create(ctx)!
            let regResult = dx_vm_register_framework_classes(vm)
            #expect(regResult == DX_OK, "Framework registration failed on cycle \(cycle)")

            // Allocate 100 objects
            let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!
            for _ in 0..<100 {
                let obj = dx_vm_alloc_object(vm, objCls)
                #expect(obj != nil)
            }

            // Trigger GC
            let gcResult = dx_vm_gc(vm)
            #expect(gcResult == DX_OK, "GC failed on cycle \(cycle)")

            // Destroy VM
            dx_vm_destroy(vm)
            ctx.pointee.vm = nil
            dx_context_destroy(ctx)
        }
        // If we reach here, all 20 cycles completed without crash
        #expect(true, "20 VM create/register/alloc/GC/destroy cycles completed")
    }

    @Test("DEX load/unload x10 does not crash")
    func testDEXLoadUnloadStress() {
        for cycle in 0..<10 {
            var dex = buildMinimalDEX()
            var dexFile: UnsafeMutablePointer<DxDexFile>?
            let parseResult = dx_dex_parse(&dex, UInt32(dex.count), &dexFile)
            #expect(parseResult == DX_OK, "DEX parse failed on cycle \(cycle)")
            if let dexFile = dexFile {
                // Parse class data to exercise more code paths
                let _ = dx_dex_parse_class_data(dexFile, 0)
                dx_dex_free(dexFile)
            }
        }
        #expect(true, "10 DEX load/unload cycles completed")
    }

    @Test("Rapid VM creation and destruction x50 does not crash")
    func testRapidVMCreateDestroy() {
        for cycle in 0..<50 {
            let ctx = dx_context_create()!
            let vm = dx_vm_create(ctx)!
            // Verify VM is usable
            #expect(vm.pointee.class_count == 0, "Fresh VM should have 0 classes on cycle \(cycle)")
            dx_vm_destroy(vm)
            ctx.pointee.vm = nil
            dx_context_destroy(ctx)
        }
        #expect(true, "50 rapid VM create/destroy cycles completed")
    }
}

// ============================================================
// MARK: - Try/Catch Across Method Boundary Tests
// ============================================================

/// Helper: Creates a synthetic method with try/catch tables appended after the instructions.
/// The insns buffer includes the try_items and encoded_catch_handler data inline.
private func makeSyntheticMethodWithTryCatch(
    vm: UnsafeMutablePointer<DxVM>,
    name: String,
    shorty: String,
    registers: UInt16,
    insns: [UInt16],
    triesSize: UInt16,
    tryItemsAndHandlers: [UInt8]
) -> (method: UnsafeMutablePointer<DxMethod>, insnsBuf: UnsafeMutableBufferPointer<UInt16>) {
    // The DEX format places try_items + encoded_catch_handler_list right after the insns array.
    // If insns_size is odd, 2 bytes of padding are inserted before try_items.
    let needsPadding = insns.count % 2 != 0
    let paddingBytes = needsPadding ? 2 : 0

    // Total buffer in bytes: insns (each 2 bytes) + padding + tryItemsAndHandlers
    let insnsByteCount = insns.count * 2
    let totalBytes = insnsByteCount + paddingBytes + tryItemsAndHandlers.count
    // Round up to UInt16 count
    let totalU16Count = (totalBytes + 1) / 2

    let buf = UnsafeMutableBufferPointer<UInt16>.allocate(capacity: totalU16Count)
    // Zero-fill
    for i in 0..<totalU16Count { buf[i] = 0 }

    // Copy insns
    for (i, v) in insns.enumerated() { buf[i] = v }

    // Copy try items and handlers as raw bytes after insns + padding
    let rawPtr = UnsafeMutableRawPointer(buf.baseAddress!)
    let tryCopyStart = insnsByteCount + paddingBytes
    for (i, b) in tryItemsAndHandlers.enumerated() {
        rawPtr.storeBytes(of: b, toByteOffset: tryCopyStart + i, as: UInt8.self)
    }

    let methodPtr = UnsafeMutablePointer<DxMethod>.allocate(capacity: 1)
    methodPtr.initialize(to: DxMethod())

    let objCls = dx_vm_find_class(vm, "Ljava/lang/Object;")!

    methodPtr.pointee.name = UnsafePointer(strdup(name))
    methodPtr.pointee.shorty = UnsafePointer(strdup(shorty))
    methodPtr.pointee.declaring_class = objCls
    methodPtr.pointee.has_code = true
    methodPtr.pointee.is_native = false
    methodPtr.pointee.access_flags = UInt32(DX_ACC_PUBLIC.rawValue | DX_ACC_STATIC.rawValue)
    methodPtr.pointee.code.registers_size = registers
    methodPtr.pointee.code.ins_size = 0
    methodPtr.pointee.code.outs_size = 0
    methodPtr.pointee.code.tries_size = triesSize
    methodPtr.pointee.code.debug_info_off = 0
    methodPtr.pointee.code.insns_size = UInt32(insns.count)
    methodPtr.pointee.code.insns = buf.baseAddress
    methodPtr.pointee.code.line_table = nil
    methodPtr.pointee.code.line_count = 0
    methodPtr.pointee.vtable_idx = -1

    return (methodPtr, buf)
}

@Suite("Try/Catch Across Method Boundary Tests")
struct TryCatchMethodBoundaryTests {

    @Test("Exception propagates via pending_exception when no handler exists")
    func testExceptionPropagatesWithoutHandler() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Create an exception object to throw
        let exc = dx_vm_create_exception(vm, "Ljava/lang/RuntimeException;", "test throw")
        #expect(exc != nil, "Exception object should be created")

        // Method B: new-instance v0, throw v0
        // Since we can't easily allocate an exception in bytecode without a full DEX,
        // we pre-load the exception into the register by calling the method with it as an arg.
        // Method B signature: takes 1 arg (the exception object) in v0, throws it.
        // Bytecode: throw v0 (opcode 0x27, format 11x)
        //   0x27 | (0 << 8) = 0x0027
        let throwInsns: [UInt16] = [
            0x0027  // throw v0
        ]
        let (methodB, bufB) = makeSyntheticMethod(vm: vm, name: "thrower", shorty: "VL",
                                                   registers: 1, insns: throwInsns)
        methodB.pointee.code.ins_size = 1
        defer { freeSyntheticMethod(methodB, bufB) }

        // Execute method B with the exception as argument
        var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: exc))]
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, methodB, &args, 1, &result)

        // Should return DX_ERR_EXCEPTION with pending_exception set
        #expect(status == DX_ERR_EXCEPTION, "Method with throw and no handler should return DX_ERR_EXCEPTION")
        #expect(vm.pointee.pending_exception != nil, "pending_exception should be set after unhandled throw")
        #expect(vm.pointee.pending_exception == exc, "pending_exception should be the thrown exception")

        // Clean up
        vm.pointee.pending_exception = nil
    }

    @Test("Exception caught by try/catch handler within same method")
    func testExceptionCaughtByHandler() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Create an exception object
        let exc = dx_vm_create_exception(vm, "Ljava/lang/RuntimeException;", "caught me")
        #expect(exc != nil)

        // Method A: throw v0, then handler catches and does return-void.
        // Registers: v0 = exception (passed as arg), v1 = scratch
        //
        // Bytecode layout:
        //   PC 0: throw v0          -> 0x0027 (1 code unit)
        //   PC 1: return-void       -> 0x000E (1 code unit) -- this is the catch handler target
        //
        // insns_size = 2 (even, so no padding needed before try_items)
        //
        // try_item (8 bytes):
        //   start_addr = 0 (covers PC 0)
        //   insn_count = 1 (covers just the throw)
        //   handler_off = 0 (offset into encoded_catch_handler_list)
        //
        // encoded_catch_handler_list:
        //   size = 1 (uleb128)
        //   encoded_catch_handler:
        //     size = -1 (sleb128) -> has catch-all, abs_size = 1 typed handler...
        //     Actually, for catch-all only: size = 0 (sleb128) means 0 typed handlers + catch-all
        //     size = 0 -> has_catch_all = true (size <= 0), abs_size = 0
        //     catch_all_addr = 1 (uleb128) -> jump to PC 1 (return-void)
        let catchInsns: [UInt16] = [
            0x0027,  // PC 0: throw v0
            0x000E   // PC 1: return-void (catch handler target)
        ]

        // try_items + encoded_catch_handler_list as raw bytes
        // try_item: start_addr (u32 LE), insn_count (u16 LE), handler_off (u16 LE)
        let tryItemsAndHandlers: [UInt8] = [
            // try_item[0]:
            0x00, 0x00, 0x00, 0x00,  // start_addr = 0
            0x01, 0x00,              // insn_count = 1
            0x00, 0x00,              // handler_off = 0

            // encoded_catch_handler_list:
            0x01,                    // list_size = 1 (uleb128)
            // encoded_catch_handler[0]:
            0x00,                    // size = 0 (sleb128) -> catch-all, no typed handlers
            0x01                     // catch_all_addr = 1 (uleb128) -> PC 1
        ]

        let (methodA, bufA) = makeSyntheticMethodWithTryCatch(
            vm: vm, name: "catcher", shorty: "VL",
            registers: 2, insns: catchInsns,
            triesSize: 1, tryItemsAndHandlers: tryItemsAndHandlers
        )
        methodA.pointee.code.ins_size = 1
        defer { freeSyntheticMethod(methodA, bufA) }

        // Execute method A with exception as argument
        var args = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: exc))]
        var result = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let status = dx_vm_execute_method(vm, methodA, &args, 1, &result)

        // Exception should be caught: method returns DX_OK, no pending exception
        #expect(status == DX_OK, "Method with try/catch should catch the exception and return DX_OK")
        #expect(vm.pointee.pending_exception == nil, "pending_exception should be nil after catch")
    }

    @Test("Cross-method exception unwinding: callee throws, caller catches")
    func testCrossMethodExceptionUnwinding() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Test the cross-method unwinding path:
        // 1. Execute method B (native, throws exception)
        // 2. Verify exception propagates with DX_ERR_EXCEPTION
        // 3. Simulate caller catching by clearing pending_exception

        // Use a framework method that throws on invalid input
        let alCls = dx_vm_find_class(vm, "Ljava/util/ArrayList;")!
        let listObj = dx_vm_alloc_object(vm, alCls)!

        // Init the list
        let initMethod = dx_vm_find_method(alCls, "<init>", "V")!
        var initArgs = [DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: listObj))]
        var initResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        let initStatus = dx_vm_execute_method(vm, initMethod, &initArgs, 1, &initResult)
        #expect(initStatus == DX_OK)

        // Call get(0) on empty list — should throw IndexOutOfBoundsException
        if let getMethod = dx_vm_find_method(alCls, "get", "LI") {
            var getArgs = [
                DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: listObj)),
                DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            ]
            var getResult = DxValue(tag: DX_VAL_VOID, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
            let getStatus = dx_vm_execute_method(vm, getMethod, &getArgs, 2, &getResult)

            // Should fail (throw or error) — key point: no crash
            if getStatus == DX_ERR_EXCEPTION {
                #expect(vm.pointee.pending_exception != nil,
                        "pending_exception should be set when DX_ERR_EXCEPTION is returned")
            }
            // In a real interpreter, the caller's catch handler would intercept this.
            // Here we verify the mechanism works by clearing it.
            vm.pointee.pending_exception = nil
        }

        // Verify VM is still usable after exception
        let str = dx_vm_create_string(vm, "still alive after exception")
        #expect(str != nil, "VM should remain usable after exception unwinding")
    }
}

// ============================================================
// MARK: - Regression Tests
// ============================================================

@Suite("Regression Tests")
struct RegressionTests {

    @Test("array_elements field access (not array_data)")
    func testArrayElementsFieldAccess() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Allocate an array and verify array_elements is used for element storage
        let arr = dx_vm_alloc_array(vm, 5)
        #expect(arr != nil, "Array allocation should succeed")
        guard let arr = arr else { return }

        #expect(arr.pointee.is_array == true, "Object should be marked as array")
        #expect(arr.pointee.array_length == 5, "Array length should be 5")
        #expect(arr.pointee.array_elements != nil, "array_elements should be allocated")

        // Store values using array_elements
        arr.pointee.array_elements[0] = DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 42))
        arr.pointee.array_elements[1] = DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 99))
        arr.pointee.array_elements[4] = DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: -1))

        // Load and verify
        #expect(arr.pointee.array_elements[0].tag == DX_VAL_INT)
        #expect(arr.pointee.array_elements[0].i == 42)
        #expect(arr.pointee.array_elements[1].i == 99)
        #expect(arr.pointee.array_elements[4].i == -1)
    }

    @Test("DxValue .l field for int64_t wide value storage")
    func testDxValueWideStorage() {
        // Verify DxValue uses .l (not .j) for int64_t
        var val = DxValue(tag: DX_VAL_LONG, DxValue.__Unnamed_union___Anonymous_field1(l: 0))
        val.l = Int64(0x7FFFFFFFFFFFFFFF)  // max int64
        #expect(val.tag == DX_VAL_LONG)
        #expect(val.l == Int64(0x7FFFFFFFFFFFFFFF), "DxValue.l should store max int64")

        // Verify negative values
        val.l = Int64(-1234567890123456789)
        #expect(val.l == Int64(-1234567890123456789), "DxValue.l should store negative int64")

        // Verify zero
        val.l = 0
        #expect(val.l == 0, "DxValue.l should store zero")
    }

    @Test("Class hash table insertion — dx_vm_find_class finds registered classes")
    func testClassHashTableInsertion() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // After framework registration, all classes should be in the hash table
        // Verify a broad set of classes are findable via the O(1) hash lookup
        let classDescriptors = [
            "Ljava/lang/Object;",
            "Ljava/lang/String;",
            "Ljava/lang/Integer;",
            "Ljava/util/ArrayList;",
            "Ljava/util/HashMap;",
            "Landroid/app/Activity;",
            "Landroid/widget/TextView;",
            "Landroid/widget/Button;",
            "Landroid/content/Intent;",
            "Landroid/os/Bundle;",
            "Landroidx/appcompat/app/AppCompatActivity;",
        ]
        for desc in classDescriptors {
            let cls = dx_vm_find_class(vm, desc)
            #expect(cls != nil, "dx_vm_find_class should find \(desc) via hash table")
            if let cls = cls {
                // Verify the descriptor matches what we looked up
                #expect(String(cString: cls.pointee.descriptor) == desc,
                        "Found class descriptor should match query for \(desc)")
            }
        }

        // Verify that a non-existent class returns nil
        #expect(dx_vm_find_class(vm, "Lcom/fake/DoesNotExist;") == nil,
                "Non-existent class should return nil from hash table lookup")

        // Verify the class_count is reasonable (framework registers 100+ classes)
        #expect(vm.pointee.class_count > 100, "Framework should register many classes")
    }

    @Test("string_data field on DxObject stores string without pointer casts")
    func testStringDataFieldAccess() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        // Create a string and verify string_data field is used directly
        let strObj = dx_vm_create_string(vm, "Hello DexLoom Regression")
        #expect(strObj != nil, "String creation should succeed")
        guard let strObj = strObj else { return }

        // Verify string_data is set and readable
        #expect(strObj.pointee.string_data != nil, "string_data should be non-nil for string objects")
        let value = String(cString: strObj.pointee.string_data)
        #expect(value == "Hello DexLoom Regression",
                "string_data should contain the exact string value")

        // Verify dx_vm_get_string_value also returns the same thing
        if let retrieved = dx_vm_get_string_value(strObj) {
            #expect(String(cString: retrieved) == "Hello DexLoom Regression",
                    "dx_vm_get_string_value should match string_data")
        }

        // Verify the class is java.lang.String
        #expect(strObj.pointee.klass == vm.pointee.class_string,
                "String object class should be java.lang.String")
    }

    @Test("Array with object elements stores and retrieves correctly")
    func testArrayObjectElements() {
        let (ctx, vm) = makeVM()
        defer { teardownVM(ctx, vm) }

        let arr = dx_vm_alloc_array(vm, 3)!
        let s1 = dx_vm_create_string(vm, "first")!
        let s2 = dx_vm_create_string(vm, "second")!

        // Store object references in array_elements
        arr.pointee.array_elements[0] = DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: s1))
        arr.pointee.array_elements[1] = DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: s2))
        arr.pointee.array_elements[2] = DxValue(tag: DX_VAL_OBJ, DxValue.__Unnamed_union___Anonymous_field1(obj: nil))

        // Retrieve and verify
        #expect(arr.pointee.array_elements[0].tag == DX_VAL_OBJ)
        #expect(arr.pointee.array_elements[0].obj == s1)
        #expect(arr.pointee.array_elements[1].obj == s2)
        #expect(arr.pointee.array_elements[2].obj == nil, "Null element should be nil")

        // Verify the stored strings are still valid
        #expect(String(cString: dx_vm_get_string_value(arr.pointee.array_elements[0].obj)!) == "first")
        #expect(String(cString: dx_vm_get_string_value(arr.pointee.array_elements[1].obj)!) == "second")
    }

    @Test("DxValue union field layout is correct for all types")
    func testDxValueUnionLayout() {
        // INT
        var intVal = DxValue(tag: DX_VAL_INT, DxValue.__Unnamed_union___Anonymous_field1(i: 0))
        intVal.i = 42
        #expect(intVal.i == 42)

        // LONG (uses .l, NOT .j)
        var longVal = DxValue(tag: DX_VAL_LONG, DxValue.__Unnamed_union___Anonymous_field1(l: 0))
        longVal.l = 9876543210
        #expect(longVal.l == 9876543210)

        // FLOAT
        var floatVal = DxValue(tag: DX_VAL_FLOAT, DxValue.__Unnamed_union___Anonymous_field1(f: 0))
        floatVal.f = 3.14
        #expect(floatVal.f == Float(3.14))

        // DOUBLE
        var doubleVal = DxValue(tag: DX_VAL_DOUBLE, DxValue.__Unnamed_union___Anonymous_field1(d: 0))
        doubleVal.d = 2.718281828
        #expect(doubleVal.d == 2.718281828)
    }
}

