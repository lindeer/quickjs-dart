import 'dart:async' show Completer;
import 'dart:isolate';

import 'src/js_eval_result.dart';
import 'src/native_js_engine.dart';

export 'src/js_eval_result.dart';

/// Javascript engine object in main isolate.
final class JsEngine {
  final int _id;
  final JsEngineManager _manager;

  JsEngine._(this._id, this._manager);

  /// Evaluate the given [code]. The [code] would send to native engine isolate.
  Future<JsEvalResult> eval(String code) => _manager.eval(_id, code);

  /// Notify the engine isolate to dispose this engine.
  Future<void> dispose() => _manager.disposeEngine(_id);

  @override
  String toString() => '{"id":$_id}';
}

/// A manager class that setup an isolate and communicate with it. All
/// `NativeJsEngine` are active in this isolate.
final class JsEngineManager {
  final ReceivePort _recv;
  final Isolate _isolate;
  final SendPort _send;
  final _engines = <int, JsEngine>{};
  final _futures = <Completer>[];

  JsEngineManager._(this._recv, this._isolate, this._send);

  /// Async create a manager instance. One instance one isolate.
  static Future<JsEngineManager> create() async {
    final recv = ReceivePort('main.incoming');
    final isolate = await Isolate.spawn<SendPort>(
      engineIsolate,
      recv.sendPort,
      errorsAreFatal: true,
      debugName: '_engineIsolate',
    );
    final receiving = recv.asBroadcastStream();
    final send = (await receiving.first) as SendPort;
    final data = receiving.cast<Map<String, dynamic>>();
    final manager = JsEngineManager._(recv, isolate, send);
    data.listen(manager._onDataArrived);
    return manager;
  }

  /// To create an engine instance with [filename] and [code].
  /// [filename] would be used as a tag for error report.
  /// [code] would be treat as a js module to evaluate.
  Future<JsEngine> createEngine(String filename, {String? code}) async {
    return _sendWaitFor({
      'cmd': 'create',
      'filename': filename,
      if (code != null) 'code': code,
    });
  }

  void _onCreated(Map<String, dynamic> data) {
    final c = _futures.removeAt(0) as Completer<JsEngine>;
    final result = JsEvalResult.from(data);
    final err = result.stderr;
    if (err != null) {
      c.completeError(err);
      return;
    }

    final id = data['id'] ?? 0;
    if (id < 1) {
      c.completeError("Illegal engine id: '$id'");
      return;
    }
    final e = JsEngine._(id, this);
    _engines[id] = e;
    c.complete(e);
  }

  /// Specify an js engine with [id] to evaluate the give [code]. If not
  /// specified, [type] would be `global`.
  Future<JsEvalResult> eval(int id, String code, {EvalType? type}) async {
    return _sendWaitFor({
      'cmd': 'eval',
      'id': id,
      'code': code,
      if (type != null) 'type': type.index,
    });
  }

  void _onEvalDone(Map<String, dynamic> data) {
    final c = _futures.removeAt(0) as Completer<JsEvalResult>;
    final result = JsEvalResult.from(data);
    final err = result.stderr;
    err != null ? c.completeError(err) : c.complete(result);
  }

  /// Dispose an js engine with [id].
  Future<void> disposeEngine(int id) async {
    print("engine-$id: disposing...");
    return _sendWaitFor({
      'cmd': 'dispose',
      'id': id,
    });
  }

  void _onDisposed(Map<String, dynamic> data) {
    final c = _futures.removeAt(0) as Completer<void>;
    final targetId = data['id'] ?? 0;
    if (targetId < 1) {
      c.completeError("Engine id: '$targetId' not exists!");
      return;
    }
    _engines.remove(targetId);
    c.complete();
    print("engine-$targetId: disposed.");
  }

  /// Notify native js engines in the isolate to dispose and then kill this
  /// isolate.
  Future<void> dispose() async {
    print("manager: disposing native engines ...");
    return _sendWaitFor(closeCommand);
  }

  void _onClosed(Map<String, dynamic> data) {
    final c = _futures.removeAt(0) as Completer<void>;
    c.complete();
    print("manager: native engines disposed.");
    _recv.close();
    _isolate.kill();
  }

  /// Current engine counts.
  int get length => _engines.length;

  Future<T> _sendWaitFor<T>(Map<String, dynamic> data) {
    _send.send(data);
    final c = Completer<T>();
    _futures.add(c);
    return c.future;
  }

  void _onDataArrived(Map<String, dynamic> data) {
    final cmd = data['cmd'];
    switch (cmd) {
      case 'create':
        _onCreated(data);
        break;
      case 'eval':
        _onEvalDone(data);
        break;
      case 'dispose':
        _onDisposed(data);
        break;
      case closeCommandKey:
        _onClosed(data);
        break;
    }
  }
}
