import 'dart:async' show Completer;
import 'dart:isolate';

import 'src/js_eval_result.dart';
import 'src/native_js_engine.dart';

export 'src/js_eval_result.dart';
export 'src/native_js_engine.dart' show JSNotifyFunction;

/// Javascript engine object in main isolate.
final class JsEngine {
  final int _id;
  final JsEngineManager _manager;
  final _notifiers = <String, JSNotifyFunction>{};

  JsEngine._(this._id, this._manager);

  /// Evaluate the given [code]. The [code] would send to native engine isolate.
  Future<JsEvalResult> eval(String code) => _manager.eval(_id, code);

  /// Notify the engine isolate to dispose this engine.
  Future<void> dispose() => _manager.disposeEngine(_id);

  /// Bind the [method] in js world with [func] in Dart world.
  void registerBridge(String method, JSNotifyFunction? func) {
    if (func == null) {
      _notifiers.remove(method);
    } else {
      _notifiers[method] = func;
    }
  }

  @override
  String toString() => '{"id":$_id}';
}

/// A manager class that setup an isolate and communicate with it. All
/// `NativeJsEngine` are active in this isolate.
final class JsEngineManager {
  final ReceivePort _recv;
  final ReceivePort _notified;
  final Isolate _isolate;
  final SendPort _send;
  final bool verbose;
  final _engines = <int, JsEngine>{};
  final _futures = <Completer<Map<String, dynamic>>>[];

  JsEngineManager._(
    this._recv,
    this._notified,
    this._isolate,
    this._send,
    this.verbose,
  );

  void log(String info) {
    if (verbose) {
      print("[${DateTime.now().toString()}] $info");
    }
  }

  /// Async create a manager instance. One instance one isolate.
  static Future<JsEngineManager> create({
    bool verbose = false,
  }) async {
    final recv = ReceivePort('main.incoming');
    final notified = ReceivePort('main.notified');
    final isolate = await Isolate.spawn<(SendPort, SendPort, bool)>(
      engineIsolate,
      (recv.sendPort, notified.sendPort, verbose),
      errorsAreFatal: true,
      debugName: '_engineIsolate',
    );
    final receiving = recv.asBroadcastStream();
    final send = (await receiving.first) as SendPort;
    final data = receiving.cast<Map<String, dynamic>>();
    final manager = JsEngineManager._(recv, notified, isolate, send, verbose);
    data.listen(manager._onDataArrived);
    notified.cast<Map<String, dynamic>>().listen(manager._onNotified);
    return manager;
  }

  /// To create an engine instance with [filename] and [code].
  /// [filename] would be used as a tag for error report.
  /// [code] would be treat as a js module to evaluate.
  Future<JsEngine> createEngine(String filename, {String? code}) async {
    final data = await _sendWaitFor({
      'cmd': 'create',
      'filename': filename,
      if (code != null) 'code': code,
    });
    final result = JsEvalResult.from(data);
    final err = result.stderr;
    if (err != null) {
      throw Exception('Engine create failed: $err');
    }

    final id = data['id'] ?? 0;
    if (id < 1) {
      throw Exception("Illegal engine created: '$id'");
    }
    final e = JsEngine._(id, this);
    _engines[id] = e;
    return e;
  }

  /// Specify an js engine with [id] to evaluate the give [code]. If not
  /// specified, [type] would be `global`.
  Future<JsEvalResult> eval(int id, String code, {EvalType? type}) async {
    final data = await _sendWaitFor({
      'cmd': 'eval',
      'id': id,
      'code': code,
      if (type != null) 'type': type.index,
    });
    final result = JsEvalResult.from(data);
    final err = result.stderr;
    if (err != null) {
      throw Exception('Engine eval failed: $err');
    }
    return result;
  }

  /// Dispose an js engine with [id].
  Future<void> disposeEngine(int id) async {
    log("engine-$id: disposing...");
    final data = await _sendWaitFor({
      'cmd': 'dispose',
      'id': id,
    });
    final targetId = data['id'] ?? 0;
    if (targetId < 1) {
      log("Engine '$targetId' not exists!");
    }
    _engines.remove(targetId);
    log("engine-$targetId: disposed.");
  }

  /// Notify native js engines in the isolate to dispose and then kill this
  /// isolate.
  Future<void> dispose() async {
    log("manager: disposing native engines ...");
    await _sendWaitFor(closeCommand);
    log("manager: native engines disposed.");
    _recv.close();
    _notified.close();
    _isolate.kill();
  }

  void _onNotified(Map<String, dynamic> data) {
    final targetId = data['id'] ?? 0;
    if (targetId < 1) {
      log("manager: notified '$targetId' not exists!");
      return;
    }
    final e = _engines[targetId];
    if (e == null) {
      log("manager: notified '$targetId' not found!");
      return;
    }
    final method = data['method'];
    final params = data['data'] as Map<String, dynamic>;
    e._notifiers[method]?.call(params);
    log("manager: $e.$method($params) notified.");
  }

  /// Current engine counts.
  int get length => _engines.length;

  Future<Map<String, dynamic>> _sendWaitFor(Map<String, dynamic> data) {
    _send.send(data);
    final c = Completer<Map<String, dynamic>>();
    _futures.add(c);
    return c.future;
  }

  void _onDataArrived(Map<String, dynamic> data) {
    final c = _futures.removeAt(0);
    c.complete(data);
  }
}
