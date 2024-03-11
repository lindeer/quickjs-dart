import 'dart:ffi' as ffi;

import 'common.dart' as c;
import 'ffi.dart';
import 'js_eval_result.dart';
import 'lib_quickjs.dart' as lib;

typedef _DartJSCFunction = lib.JSValue Function(ffi.Pointer<lib.JSContext> ctx,
    lib.JSValue val, ffi.Int argc, ffi.Pointer<lib.JSValue> argv);

/// The JsEngine that directly interop with C API.
final class NativeJsEngine {
  final ffi.Pointer<lib.JSRuntime> rt;
  final ffi.Pointer<lib.JSContext> ctx;

  /// A char buffer for interoperation with C.
  final NativeString _buf;
  final _stdout = StringBuffer();

  NativeJsEngine._(this.rt, this.ctx, this._buf);

  factory NativeJsEngine({String? name}) {
    final rt = lib.JS_NewRuntime();
    final ctx = lib.JS_NewContext(rt);
    final cStr = NativeString();
    final e = NativeJsEngine._(rt, ctx, cStr);
    _bindConsole(ctx, e);
    cStr.pavedBy(name ?? '<input>');
    return e;
  }

  /// Evaluate the give code.
  JsEvalResult eval(String code) {
    final buf = NativeString.from(code);
    final result = lib.JS_Eval(
      ctx,
      buf.pointer,
      buf.length,
      _buf.pointer,
      lib.JS_EVAL_TYPE_GLOBAL,
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

  static void _bindConsole(ffi.Pointer<lib.JSContext> ctx, NativeJsEngine e) {
    final global = lib.JS_GetGlobalObject(ctx);

    final buf = e._buf;
    final name = buf.pavedBy('log');
    final console = lib.JS_NewObject(ctx);
    final pointer = ffi.Pointer.fromFunction<_DartJSCFunction>(_consoleLog);
    final func = c.JS_NewCFunction(ctx, pointer, name, 1);
    lib.JS_SetPropertyStr(ctx, console, name, func);
    lib.JS_SetPropertyStr(ctx, global, buf.pavedBy('console'), console);
    _consoleDict[c.hashJsValue(console)] = e;

    c.JS_FreeValue(ctx, global);
  }
}
