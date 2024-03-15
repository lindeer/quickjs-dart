import 'dart:convert' show json;
import 'dart:ffi' as ffi;

import 'common.dart' as c;
import 'ffi.dart';
import 'js_eval_result.dart';
import 'lib_quickjs.dart' as lib;

typedef _DartJSCFunction = lib.JSValue Function(ffi.Pointer<lib.JSContext> ctx,
    lib.JSValue val, ffi.Int argc, ffi.Pointer<lib.JSValue> argv);

typedef _DartJSModuleLoadFunc = ffi.Pointer<lib.JSModuleDef> Function(
    ffi.Pointer<lib.JSContext> ctx,
    ffi.Pointer<ffi.Char> name,
    ffi.Pointer<ffi.Void> opaque);

typedef DartStringReader = String Function(String name);

/// A notify function that receive the changed data.
typedef JSNotifyFunction = void Function(Map<String, dynamic> data);

enum EvalType {
  global,
  module,
}

/// The JsEngine that directly interop with C API.
final class NativeJsEngine {
  final ffi.Pointer<lib.JSRuntime> rt;
  final ffi.Pointer<lib.JSContext> ctx;

  /// A char buffer for interoperation with C.
  final NativeString _buf;
  final _stdout = StringBuffer();
  final _notifyDict = <String, JSNotifyFunction>{};

  NativeJsEngine._(this.rt, this.ctx, this._buf);

  factory NativeJsEngine({String? name}) {
    final rt = lib.JS_NewRuntime();
    final ctx = lib.JS_NewContext(rt);
    final cStr = NativeString();
    final e = NativeJsEngine._(rt, ctx, cStr);
    final globalThis = lib.JS_GetGlobalObject(ctx);
    e._bindConsole(globalThis, 'console');
    e._bindNotify(globalThis, '_ffiNotify');
    final pf = ffi.Pointer.fromFunction<_DartJSModuleLoadFunc>(_loadJsModule);
    lib.JS_SetModuleLoaderFunc(rt, ffi.nullptr, pf, ffi.nullptr);
    cStr.pavedBy(name ?? '<input>');
    c.JS_FreeValue(ctx, globalThis);
    return e;
  }

  /// Evaluate the give code.
  JsEvalResult eval(String code, {EvalType evalType = EvalType.global}) {
    final buf = NativeString.from(code);
    final result = lib.JS_Eval(
      ctx,
      buf.pointer,
      buf.length,
      _buf.pointer,
      evalType == EvalType.global
          ? lib.JS_EVAL_TYPE_GLOBAL
          : lib.JS_EVAL_TYPE_MODULE,
    );

    String? err;
    if (c.JS_IsException(result)) {
      err = c.getJsError(ctx);
    }
    final value = c.toDartString(ctx, result) ?? '(null)';
    c.JS_FreeValue(ctx, result);
    buf.dispose();
    final out = _stdout.length > 0 ? _stdout.toString() : null;
    _stdout.clear();

    return JsEvalResult(
      value: value,
      stdout: out,
      stderr: err,
    );
  }

  /// Release the native resources.
  void dispose() {
    _buf.dispose();

    lib.JS_FreeContext(ctx);
    lib.JS_FreeRuntime(rt);
  }

  static final _consoleDict = <int, NativeJsEngine>{};

  static lib.JSValue _consoleLog(ffi.Pointer<lib.JSContext> ctx,
      lib.JSValue val, int argc, ffi.Pointer<lib.JSValue> argv) {
    final strings = List.generate(argc, (i) {
      final arg = argv[i];
      final ptr = lib.JS_ToCStringLen2(ctx, ffi.nullptr, arg, 0);
      if (ptr == ffi.nullptr) {
        return '';
      }
      final str = NativeString.toDartString(ptr);
      lib.JS_FreeCString(ctx, ptr);
      return str;
    }).join(' ');

    final engine = _consoleDict[c.hashJsValue(val)];
    if (engine == null) {
      print("Engine instance not found with '$strings'!");
    } else {
      engine._stdout.writeln(strings);
    }
    return c.JS_UNDEFINED;
  }

  void _bindConsole(lib.JSValue globalThis, String name) {
    final str = _buf.pavedBy('log');
    final console = lib.JS_NewObject(ctx);
    final pf = ffi.Pointer.fromFunction<_DartJSCFunction>(_consoleLog);
    final func = c.JS_NewCFunction(ctx, pf, str, 1);
    lib.JS_SetPropertyStr(ctx, console, str, func);
    lib.JS_SetPropertyStr(ctx, globalThis, _buf.pavedBy(name), console);
    _consoleDict[c.hashJsValue(console)] = this;
  }

  static DartStringReader? strReader;

  static ffi.Pointer<lib.JSModuleDef> _loadJsModule(
    ffi.Pointer<lib.JSContext> ctx,
    ffi.Pointer<ffi.Char> name,
    ffi.Pointer<ffi.Void> opaque,
  ) {
    final path = NativeString.toDartString(name);
    final code = strReader?.call(path);
    if (code == null) {
      return ffi.nullptr;
    }
    final buf = NativeString.from(code);
    final funcVal = lib.JS_Eval(ctx, buf.pointer, buf.length, name,
        lib.JS_EVAL_TYPE_MODULE | lib.JS_EVAL_FLAG_COMPILE_ONLY);
    buf.dispose();
    if (c.JS_IsException(funcVal)) {
      return ffi.nullptr;
    }
    final module = c.JS_VALUE_GET_PTR(funcVal).cast<lib.JSModuleDef>();
    c.JS_FreeValue(ctx, funcVal);
    return module;
  }

  /// For a js global variable [name], bridge it with a ffi callback by [type].
  bool bridgeNotifyObject(String name) {
    final globalThis = lib.JS_GetGlobalObject(ctx);
    final obj = lib.JS_GetPropertyStr(ctx, globalThis, _buf.pavedBy(name));

    if (c.JS_IsException(obj)) {
      print('Error: bridgeJsObject: ${c.getJsError(ctx)}');
      return false;
    }
    _notifyEngineDict[c.hashJsValue(obj)] = this;

    c.JS_FreeValue(ctx, obj);
    c.JS_FreeValue(ctx, globalThis);
    return true;
  }

  /// Register a [func] method with [name] that receive the changed data.
  /// Remove the [name] callback if [func] is null.
  void registerNotify(String name, JSNotifyFunction? func) {
    if (func == null) {
      _notifyDict.remove(name);
    } else {
      _notifyDict[name] = func;
    }
  }

  /// The dict map an js object to an engine instance for function2.
  static final _notifyEngineDict = <int, NativeJsEngine>{};

  /// Bind ffi callback with the global object
  void _bindNotify(lib.JSValue globalThis, String name) {
    final pf = ffi.Pointer.fromFunction<_DartJSCFunction>(_dartOnNotified);
    final func = c.JS_NewCFunction(ctx, pf, ffi.nullptr, 2);
    lib.JS_SetPropertyStr(ctx, globalThis, _buf.pavedBy(name), func);
  }

  /// The ffi callback that handle the js functions with 2 params.
  static lib.JSValue _dartOnNotified(ffi.Pointer<lib.JSContext> ctx,
      lib.JSValue val, int argc, ffi.Pointer<lib.JSValue> argv) {
    final method = lib.JS_ToCStringLen2(ctx, ffi.nullptr, argv[0], 0);
    final data = lib.JS_ToCStringLen2(ctx, ffi.nullptr, argv[1], 0);
    final m = NativeString.toDartString(method);
    final d = NativeString.toDartString(data);

    final engine = _notifyEngineDict[c.hashJsValue(val)];
    final func = engine?._notifyDict[m];
    if (func != null) {
      final map = json.decode(d);
      func.call(map);
    } else {
      final warning = engine == null
          ? 'Engine instance not found!'
          : "'$m' method not found!";
      print('Warning: $warning');
    }
    if (method != ffi.nullptr) {
      lib.JS_FreeCString(ctx, method);
    }
    if (data != ffi.nullptr) {
      lib.JS_FreeCString(ctx, data);
    }
    return c.JS_UNDEFINED;
  }
}
