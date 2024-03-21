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

  /*
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
   */
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

  tearDownAll(() async {
    await manager.dispose();
  });
}
