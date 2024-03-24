import 'dart:async' show Timer;
import 'dart:convert' show json;
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart' show calloc;
import 'package:meta/meta.dart' show visibleForTesting;

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
typedef DartNotifier = void Function(
    NativeJsEngine engine, String method, Map<String, dynamic> data);

/// A notify function that receive the changed data.
typedef JSNotifyFunction = void Function(Map<String, dynamic> data);

enum EvalType {
  global,
  module,
}

/// The JsEngine that directly interop with C API.
final class NativeJsEngine {
  final int _id;
  final ffi.Pointer<lib.JSContext> ctx;
  final String filename;
  final _stdout = StringBuffer();
  Map<String, JSNotifyFunction>? _notifyDict;

  NativeJsEngine._(this._id, this.ctx, this.filename);

  /// Create a engine instance with [code] as module
  factory NativeJsEngine({String? name, String? code}) {
    final (e, r) = _manager.createEngine(name ?? '<input>', code);
    final err = r?.stderr;
    if (err != null) {
      throw Exception(err);
    }
    return e;
  }

  /// Evaluate the give code.
  JsEvalResult eval(String code, {EvalType evalType = EvalType.global}) {
    final buf = NativeString.from(code);
    final result = lib.JS_Eval(
      ctx,
      buf.pointer,
      buf.length,
      _manager.buf.pavedBy(filename),
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
    lib.JS_FreeContext(ctx);
    _manager.onDisposed(this);
  }

  static lib.JSValue _consoleLog(ffi.Pointer<lib.JSContext> ctx,
      lib.JSValue val, int argc, ffi.Pointer<lib.JSValue> argv) {
    return _manager.bindConsoleLog(ctx, val, argc, argv);
  }

  void _bindConsole(lib.JSValue globalThis, String name) {
    // ignore: no_leading_underscores_for_local_identifiers
    final _buf = _manager.buf;
    final str = _buf.pavedBy('log');
    final console = lib.JS_NewObject(ctx);
    final pf = ffi.Pointer.fromFunction<_DartJSCFunction>(_consoleLog);
    final func = c.JS_NewCFunction(ctx, pf, str, 1);
    lib.JS_SetPropertyStr(ctx, console, str, func);
    lib.JS_SetPropertyStr(ctx, globalThis, _buf.pavedBy(name), console);
    _manager._consoleDict[c.hashJsValue(console)] = this;
  }

  /// Set a global string reader function in Dart world, it would load js code
  /// from the give [name], may be a time-consumed operation.
  static set strReader(DartStringReader? reader) {
    _manager.strReader = reader;
  }

  /// Set a global notify function in Dart world, or else find the right engine,
  /// and call its registered notify function by [registerNotify].
  static set onDartNotifier(DartNotifier? notifier) {
    _manager.onDartNotified = notifier;
  }

  /// For a js global variable [name], bridge it with a ffi callback by [type].
  bool bridgeNotifyObject(String name) {
    final globalThis = lib.JS_GetGlobalObject(ctx);
    final str = _manager.buf.pavedBy(name);
    final obj = lib.JS_GetPropertyStr(ctx, globalThis, str);

    if (c.JS_IsException(obj)) {
      print('Error: bridgeJsObject: ${c.getJsError(ctx)}');
      return false;
    }
    _manager._notifyEngineDict[c.hashJsValue(obj)] = this;

    c.JS_FreeValue(ctx, obj);
    c.JS_FreeValue(ctx, globalThis);
    return true;
  }

  /// Register a [func] method with [name] that receive the changed data.
  /// Remove the [name] callback if [func] is null.
  void registerNotify(String name, JSNotifyFunction? func) {
    final dict = _notifyDict;
    if (func == null) {
      if (dict != null) {
        dict.remove(name);
      }
    } else {
      if (dict != null) {
        dict[name] = func;
      } else {
        _notifyDict = {
          name: func,
        };
      }
    }
  }

  /// Bind ffi callback with the global object
  void _bindNotify(lib.JSValue globalThis, String name) {
    final pf = ffi.Pointer.fromFunction<_DartJSCFunction>(_dartOnNotified);
    final func = c.JS_NewCFunction(ctx, pf, ffi.nullptr, 2);
    // ignore: no_leading_underscores_for_local_identifiers
    final _buf = _manager.buf;
    lib.JS_SetPropertyStr(ctx, globalThis, _buf.pavedBy(name), func);
  }

  /// The ffi callback that handle the js functions with 2 params.
  static lib.JSValue _dartOnNotified(ffi.Pointer<lib.JSContext> ctx,
      lib.JSValue val, int argc, ffi.Pointer<lib.JSValue> argv) {
    return _manager.onNotified(ctx, val, argc, argv);
  }

  void _bindSetTimer(lib.JSValue globalThis, String name) {
    final pf = ffi.Pointer.fromFunction<_DartJSCFunction>(_dartSetTimeout);
    final func = c.JS_NewCFunction(ctx, pf, ffi.nullptr, 2);
    // ignore: no_leading_underscores_for_local_identifiers
    final _buf = _manager.buf;
    lib.JS_SetPropertyStr(ctx, globalThis, _buf.pavedBy(name), func);
  }

  static lib.JSValue _dartSetTimeout(ffi.Pointer<lib.JSContext> ctx,
      lib.JSValue val, int argc, ffi.Pointer<lib.JSValue> argv) {
    return _manager.bindSetTimeout(ctx, val, argc, argv);
  }
}

/// Only one global instance for a Isolation. It was designed to hold engine
/// instances in one isolate.
late _EngineManager _manager;

@visibleForTesting
final class ManagerTester {
  ManagerTester() {
    _manager = _EngineManager();
  }

  void dispose() => _manager.dispose();

  int get length => _manager._engines.length;
}

final class _EngineManager {
  final ffi.Pointer<lib.JSRuntime> rt;
  final _engines = <int, NativeJsEngine>{};
  var _count = 0;
  DartStringReader? strReader;
  final _consoleDict = <int, NativeJsEngine>{};
  DartNotifier? onDartNotified;

  /// The dict map an js object to an engine instance for notification from js.
  final _notifyEngineDict = <int, NativeJsEngine>{};

  /// A char buffer of small chunk size, shared by all engines.
  final buf = NativeString();

  _EngineManager._(this.rt);

  factory _EngineManager() {
    final rt = lib.JS_NewRuntime();
    final pf = ffi.Pointer.fromFunction<_DartJSModuleLoadFunc>(_loadJsModule);
    lib.JS_SetModuleLoaderFunc(rt, ffi.nullptr, pf, ffi.nullptr);
    return _EngineManager._(rt);
  }

  /// The implementation of engine creation.
  (NativeJsEngine, JsEvalResult?) createEngine(String name, String? code) {
    final ctx = lib.JS_NewContext(rt);
    final e = NativeJsEngine._(++_count, ctx, name);
    _engines[e._id] = e;
    final globalThis = lib.JS_GetGlobalObject(ctx);
    e._bindConsole(globalThis, 'console');
    e._bindNotify(globalThis, '_ffiNotify');
    e._bindSetTimer(globalThis, 'setTimeout');
    c.JS_FreeValue(ctx, globalThis);
    JsEvalResult? result;
    if (code != null) {
      result = e.eval(code, evalType: EvalType.module);
    }
    return (e, result);
  }

  /// Notified if a engine disposed.
  void onDisposed(NativeJsEngine e) {
    _notifyEngineDict.removeWhere((key, value) => value == e);
    _consoleDict.removeWhere((key, value) => value == e);
    _engines.remove(e._id);
  }

  /// Destroy js runtime
  void dispose() {
    strReader = null;
    lib.JS_FreeRuntime(rt);
    print("js runtime terminated!");
  }

  /// Implement `console.log` for the given [ctx] within [val] object.
  lib.JSValue bindConsoleLog(ffi.Pointer<lib.JSContext> ctx, lib.JSValue val,
      int argc, ffi.Pointer<lib.JSValue> argv) {
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

  static ffi.Pointer<lib.JSModuleDef> _loadJsModule(
    ffi.Pointer<lib.JSContext> ctx,
    ffi.Pointer<ffi.Char> name,
    ffi.Pointer<ffi.Void> opaque,
  ) {
    final path = NativeString.toDartString(name);
    final code = _manager.strReader?.call(path);
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

  /// The ffi callback that handle the js functions with 2 params.
  lib.JSValue onNotified(ffi.Pointer<lib.JSContext> ctx, lib.JSValue val,
      int argc, ffi.Pointer<lib.JSValue> argv) {
    final method = lib.JS_ToCStringLen2(ctx, ffi.nullptr, argv[0], 0);
    final data = lib.JS_ToCStringLen2(ctx, ffi.nullptr, argv[1], 0);
    final m = NativeString.toDartString(method);
    final d = NativeString.toDartString(data);

    final engine = _notifyEngineDict[c.hashJsValue(val)];
    final func = onDartNotified ?? _onNotifiedDefault;
    if (engine != null) {
      final map = json.decode(d);
      func.call(engine, m, map);
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

  void _onNotifiedDefault(
      NativeJsEngine engine, String method, Map<String, dynamic> data) {
    final dict = engine._notifyDict;
    dict?[method]?.call(data);
  }

  lib.JSValue bindSetTimeout(ffi.Pointer<lib.JSContext> ctx, lib.JSValue val,
      int argc, ffi.Pointer<lib.JSValue> argv) {
    final func = argv[0];
    if (lib.JS_IsFunction(ctx, func) == 0) {
      final err = lib.JS_ThrowTypeError(ctx, buf.pavedBy('not a function'));
      return err;
    }
    final ptr = calloc.allocate<ffi.Int64>(ffi.sizeOf<ffi.Int64>());
    var delay = 0;
    try {
      if (lib.JS_ToInt64(ctx, ptr, argv[1]) != 0) {
        return c.JS_EXCEPTION;
      }
      delay = ptr.value;
    } finally {
      calloc.free(ptr);
    }

    // Save `JSValue` into memory, or else its value would be changed by Dart.
    final pv = calloc.allocate<lib.JSValue>(ffi.sizeOf<lib.JSValue>());
    // Increase the reference count for the new func object.
    pv.ref = c.JS_DupValue(ctx, func);
    Timer(Duration(milliseconds: delay), () {
      _handleCall(ctx, pv.ref);
      calloc.free(pv);
    });
    return c.JS_UNDEFINED;
  }

  static void _handleCall(ffi.Pointer<lib.JSContext> ctx, lib.JSValue func) {
    // Not necessary to increase the reference count anymore, a little different
    // from `call_handler` in `quickjs-libc.c`.
    final ret = lib.JS_Call(ctx, func, c.JS_UNDEFINED, 0, ffi.nullptr);
    if (c.JS_IsException(ret)) {
      print('_handleCall: ${c.getJsError(ctx)}');
    }
    c.JS_FreeValue(ctx, ret);
    c.JS_FreeValue(ctx, func);
  }
}

const _closeTag = '__close__';
const closeCommandKey = _closeTag;
const closeCommand = <String, dynamic>{'cmd': _closeTag};

void engineIsolate(SendPort outgoing) async {
  final incoming = ReceivePort('_isolate.incoming');
  outgoing.send(incoming.sendPort);
  final manager = _manager = _EngineManager();
  final requests = incoming.cast<Map<String, dynamic>>();
  manager.onDartNotified = (engine, method, data) {
    outgoing.send({
      'cmd': 'notify',
      'id': engine._id,
      'method': method,
      'data': data,
    });
  };
  await for (final req in requests) {
    final cmd = req['cmd'];
    if (cmd == _closeTag) {
      print("Isolate received '$cmd', start closing ...");
      break;
    }
    // Error happened by `js_check_stack_overflow` in `next_token`, which is
    // called by `js_parse_program`, and found stack top was changed by Dart
    // async.
    lib.JS_UpdateStackTop(manager.rt);
    switch (cmd) {
      case 'create':
        final filename = req['filename'];
        final code = req['code'];
        final (e, result) = manager.createEngine(filename, code);
        final data = result?.raw;
        outgoing.send({
          'cmd': cmd,
          'id': e._id,
          if (data != null) ...data,
        });
        break;
      case 'eval':
        final id = req['id'];
        final code = req['code'];
        final e = manager._engines[id];
        if (e == null) {
          throw Exception("invalid id '$id'");
        }
        final type = req['type'] == EvalType.module.index
            ? EvalType.module
            : EvalType.global;
        final result = e.eval(code, evalType: type);
        final data = result.raw;
        outgoing.send({
          'cmd': cmd,
          'id': e._id,
          ...data,
        });
        break;
      case 'dispose':
        final id = req['id'];
        final e = manager._engines[id];
        if (e == null) {
          print("engine id '$id' not found!");
          break;
        }
        e.dispose();
        outgoing.send({
          'cmd': cmd,
          'id': e._id,
        });
        break;
      case 'bind':
        final id = req['id'];
        final e = manager._engines[id];
        if (e == null) {
          print("engine '$id' not found by '$cmd'!");
          break;
        }
        final name = req['name'] as String;
        final b = e.bridgeNotifyObject(name);
        outgoing.send({
          'ok': b,
          ...req,
        });
        break;
    }
  }
  manager.dispose();
  outgoing.send(closeCommand);
}
