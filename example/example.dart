import 'package:quickjs/quickjs.dart';
import 'package:quickjs/src/native_js_engine.dart';

void main() {
  _runAsync();
  _runSync();
  _registerBridge(5);
}

void _runAsync() async {
  final manager = await JsEngineManager.create();
  final engine = await manager.createEngine('tag');
  final result = await engine.eval('console.log(3+4);');
  print(result.stdout?.trim());
  await engine.dispose();
  await manager.dispose();
}

void _runSync() {
  final manager = NativeEngineManager();
  final engine = NativeJsEngine(name: 'tag');
  final result = engine.eval('3-4');
  print(result.value);
  engine.dispose();
  manager.dispose();
}

void _registerBridge(int n) async {
  final manager = await JsEngineManager.create();
  final engine = await manager.createEngine('tag');
  engine.registerBridge('_onDataChanged', (data) {
    print('notified from js: $data');
  });
  final code = """
let obj = {
  update(v) {
    let s = JSON.stringify(v);
    console.log(`update: \${s}`);
    _ffiNotify("_onDataChanged", s);
    return s;
  }
};
obj.update({"key": $n});
  """;
  final result = await engine.eval(code);
  print("eval result: '${result.value}'");
  print("eval stdout: '${result.stdout?.trim()}'");
  await engine.dispose();
  await manager.dispose();
}
