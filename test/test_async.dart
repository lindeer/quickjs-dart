import 'package:quickjs/quickjs.dart';
import 'package:test/test.dart';

const _module = """
export class User {
  constructor(name) {
    this.name = name;
  }
}
globalThis.User = User;
""";

void main() async {
  final manager = await JsEngineManager.create();

  test('test async eval', () async {
    const expressions = ['3+4', 'console.log("Hello~")'];
    final engines = await Future.wait(List.generate(expressions.length, (i) {
      return manager.createEngine('<test$i>');
    }));
    final results = await Future.wait(engines.indexed.map((r) {
      final (i, e) = r;
      return e.eval(expressions[i]);
    }));
    expect(results.map((e) => e.stderr), [null, null]);
    expect(results.map((e) => e.stdout), [null, 'Hello~\n']);
    expect(results.map((e) => e.value), ['7', 'undefined']);
    expect(manager.length, 2);
    await Future.wait(engines.map((e) => e.dispose()));
    expect(manager.length, 0);
  });

  test('test async one-by-one', () async {
    const expressions = ['3+4', 'console.log("Hello~")'];
    final engines = [
      for (var i = 0; i < expressions.length; i++)
        await manager.createEngine('<test$i>'),
    ];

    final results = [
      for (final (i, e) in engines.indexed)
        await e.eval(expressions[i]),
    ];
    expect(results.map((e) => e.stderr), [null, null]);
    expect(results.map((e) => e.stdout), [null, 'Hello~\n']);
    expect(results.map((e) => e.value), ['7', 'undefined']);
    expect(manager.length, 2);
    for (final e in engines) {
      await e.dispose();
    }
    expect(manager.length, 0);
  });

  test('test async notify', () async {
    const code = """
let scope = {
  send(obj) {
    _ffiNotify("_sendMsg", JSON.stringify(obj));
  }
};
globalThis.scope = scope;
    """;
    final engines = await Future.wait(List.generate(2, (i) {
      return manager.createEngine('<test$i>', code: code);
    }));
    final ok = [0, 0];
    final results = await Future.wait(engines.indexed.expand((r) {
      final (i, e) = r;
      e.registerBridge('_sendMsg', (data) {
        ok[i] = i;
      });
      return <Future<bool>>[
        e.eval(code).then((v) => v.value.isNotEmpty),
        e.eval('scope.send({no:$i});').then((v) => v.value.isNotEmpty),
      ];
    }));
    expect(results, List.filled(4, true));
    expect(manager.length, 2);
    await Future.wait(engines.map((e) => e.dispose()));
    expect(ok, [0, 1]);
  });

  test('test event sequence', () async {
    final seq = <int>[];
    const code = '_ffiNotify("_sendMsg", JSON.stringify({}));';
    final engine = await manager.createEngine('<test-i>');
    seq.add(0);
    final result = await engine.eval(code);
    expect(result.value, 'undefined');
    seq.add(1);
    engine.registerBridge('_sendMsg', (_) {
      seq.add(2);
    });
    seq.add(3);
    await engine.eval(code);
    seq.add(4);
    await engine.dispose();
    seq.add(5);
    expect(seq, [0, 1, 3, 2, 4, 5]);
  });

  tearDownAll(() async {
    await manager.dispose();
  });
}
