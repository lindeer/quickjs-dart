import 'package:quickjs/src/native_js_engine.dart';
import 'package:test/test.dart';

void main() {
  final engine = NativeJsEngine(name: '<test>');

  test('test get js error', () {
    const errorStr = """ReferenceError: 'add' is not defined
    at <eval> (<test>)
""";
    final result = engine.eval('add(5, 3);');
    expect(result.stdout, null);
    expect(result.stderr, '$errorStr\n');
    expect(result.value, '(null)');
  });

  test('test calculation', () {
    final result = engine.eval('3 - 5');
    expect(result.stdout, null);
    expect(result.stderr, null);
    expect(result.value, '-2');
  });

  tearDownAll(() {
    engine.dispose();
  });
}
