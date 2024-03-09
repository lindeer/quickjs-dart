import 'dart:ffi' as ffi;

import 'ffi.dart';
import 'lib_quickjs.dart' as lib;

/// Implement `static inline JS_BOOL JS_IsException(JSValueConst v)` in
/// `quickjs.h`, 'cause inline functions are not supported by ffigen.
// ignore: non_constant_identifier_names
bool JS_IsException(lib.JSValue v) => v.tag == lib.JS_TAG_EXCEPTION;

/// Implement `JS_IsUndefined` macro in `quickjs.h`
// ignore: non_constant_identifier_names
bool JS_IsUndefined(lib.JSValue v) => v.tag == lib.JS_TAG_UNDEFINED;

/// Implement `static inline void JS_FreeValue(JSContext *ctx, JSValue v)` in
/// `quickjs.h`, 'cause inline functions are not supported by ffigen.
// ignore: non_constant_identifier_names
void JS_FreeValue(ffi.Pointer<lib.JSContext> ctx, lib.JSValue val) {
}

/// Implement `static inline const char *JS_ToCString(JSContext *ctx,
/// JSValueConst val1)` in `quickjs.h`.
String? _stringify(ffi.Pointer<lib.JSContext> ctx, lib.JSValue val) {
  final pointer = lib.JS_ToCStringLen2(ctx, ffi.nullptr, val, 0);
  String? str;
  if (pointer != ffi.nullptr) {
    str = NativeString.toDartString(pointer);
    lib.JS_FreeCString(ctx, pointer);
  }
  return str;
}

/// Equal with `js_dump_obj` in `quickjs-libc.c` without stderr output.
String _dumpValue(ffi.Pointer<lib.JSContext> ctx, lib.JSValue val) {
  final str = _stringify(ctx, val) ?? '[exception]';
  return '$str\n';
}

const toDartString = _stringify;

String? _errorStack(ffi.Pointer<lib.JSContext> ctx, lib.JSValue err) {
  if (lib.JS_IsError(ctx, err) == 0) {
    return null;
  }
  final buf = NativeString.from("stack");
  final val = lib.JS_GetPropertyStr(ctx, err, buf.pointer);
  final stack = JS_IsUndefined(val) ? null : _dumpValue(ctx, val);
  JS_FreeValue(ctx, val);
  buf.dispose();
  return stack;
}

/// Equal function with `js_std_dump_error` without stderr output.
String getJsError(ffi.Pointer<lib.JSContext> ctx) {
  final exception = lib.JS_GetException(ctx);
  final str = _dumpValue(ctx, exception);
  final stack = _errorStack(ctx, exception) ?? '';
  JS_FreeValue(ctx, exception);
  return '$str$stack';
}
