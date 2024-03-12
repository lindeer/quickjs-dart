import 'dart:io';

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

  test('test console.log', () {
    final result = engine.eval("console.log('Hello~');console.log('World!');");
    expect(result.stdout, 'Hello~\nWorld!\n');
    expect(result.stderr, null);
    expect(result.value, 'undefined');
  });

  test('test js import', () {
    const module = """
export class User {
  constructor(name) {
    this.name = name;
  }
}
""";
    const code = "import {User} from './user.js';";
    const exe = "var user = new User('Alem');console.log(user.name);";
    const errorSyntax = """SyntaxError: expecting '('
    at <test>:1
""";
    const errorRef = """ReferenceError: 'User' is not defined
    at <eval> (<test>:1)
""";
    String moduleReader(String _) => module;
    NativeJsEngine.strReader = moduleReader;
    var result = engine.eval(code);
    expect(result.stdout, null);
    expect(result.stderr, '$errorSyntax\n');
    expect(result.value, '(null)');

    result = engine.eval('$code$exe', evalType: EvalType.module);
    expect(result.stdout, 'Alem\n');
    expect(result.stderr, null);
    expect(result.value, '[object Promise]');

    result = engine.eval(exe);
    expect(result.stdout, null);
    expect(result.stderr, '$errorRef\n');
    expect(result.value, '(null)');

    engine.eval('$code globalThis.User=User;', evalType: EvalType.module);
    result = engine.eval(exe);
    expect(result.stdout, 'Alem\n');
    expect(result.stderr, null);
    expect(result.value, 'undefined');
  });

  test('run quickjs tests', () {
    _runQjsTest('src/tests/test_closure.js');
    _runQjsTest('src/tests/test_language.js');
    _runQjsTest('src/tests/test_builtin.js');
    _runQjsTest('src/tests/test_loop.js');
    _runQjsTest('src/tests/test_bignum.js');
  });

  tearDownAll(() {
    engine.dispose();
  });
}

void _runQjsTest(String filepath) {
  final engine = NativeJsEngine(name: filepath);
  final code = File(filepath).readAsStringSync();
  final val = engine.eval(code);
  engine.dispose();
  expect(val.stderr, null);
}
