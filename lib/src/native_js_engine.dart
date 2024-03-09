import 'dart:ffi' as ffi;

import 'common.dart' as c;
import 'ffi.dart';
import 'js_eval_result.dart';
import 'lib_quickjs.dart' as lib;

/// The JsEngine that directly interop with C API.
final class NativeJsEngine {
  final ffi.Pointer<lib.JSRuntime> rt;
  final ffi.Pointer<lib.JSContext> ctx;

  /// A char buffer for interoperation with C.
  final NativeString _buf;

  NativeJsEngine._(this.rt, this.ctx, this._buf);

  factory NativeJsEngine({String? name}) {
    final rt = lib.JS_NewRuntime();
    final ctx = lib.JS_NewContext(rt);
    final cStr = NativeString();
    cStr.pavedBy(name ?? '<input>');
    return NativeJsEngine._(rt, ctx, cStr);
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

    return JsEvalResult(
      value: value,
      stderr: err,
    );
  }

  /// Release the native resources.
  void dispose() {
    _buf.dispose();

    lib.JS_FreeContext(ctx);
    lib.JS_FreeRuntime(rt);
  }
}
