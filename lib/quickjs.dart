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
  final Stream<Map<String, dynamic>> _receiving;
  final _engines = <int, JsEngine>{};

  JsEngineManager._(this._recv, this._isolate, this._send, this._receiving);

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
    return JsEngineManager._(recv, isolate, send, data);
  }

  /// To create an engine instance with [filename] and [code].
  /// [filename] would be used as a tag for error report.
  /// [code] would be treat as a js module to evaluate.
  Future<JsEngine> createEngine(String filename, {String? code}) async {
    _send.send({
      'cmd': 'create',
      'filename': filename,
      if (code != null) 'code': code,
    });
    final data = await _receiving.first;
    final result = JsEvalResult.from(data);
    if (result.isError) {
      throw Exception(result.stderr);
    }

    final id = data['id'] ?? 0;
    if (id < 1) {
      throw Exception("Illegal engine id: '$id'");
    }
    final e = JsEngine._(id, this);
    _engines[id] = e;
    return e;
  }

  /// Specify an js engine with [id] to evaluate the give [code]. If not
  /// specified, [type] would be `global`.
  Future<JsEvalResult> eval(int id, String code, {EvalType? type}) async {
    _send.send({
      'cmd': 'eval',
      'id': id,
      'code': code,
      if (type != null) 'type': type.index,
    });
    final data = await _receiving.first;
    final result = JsEvalResult.from(data);
    return result;
  }

  /// Dispose an js engine with [id].
  Future<void> disposeEngine(int id) async {
    print("engine-$id: disposing...");
    _send.send({
      'cmd': 'dispose',
      'id': id,
    });
    final data = await _receiving.first;
    final targetId = data['id'] ?? 0;
    _engines.remove(targetId);
    print("engine-$targetId: disposed.");
  }

  /// Notify native js engines in the isolate to dispose and then kill this
  /// isolate.
  Future<void> dispose() async {
    print("manager: disposing native engines ...");
    _send.send(closeCommand);
    await _receiving.first;
    print("manager: native engines disposed.");
    _recv.close();
    _isolate.kill();
  }

  /// Current engine counts.
  int get length => _engines.length;
}
