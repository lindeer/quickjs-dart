
A dart binding of [quickjs](https://bellard.org/quickjs/) with latest ffi tool native_assets_cli.

Inspired by [flutter_js](https://pub.dev/packages/flutter_js), quickjs-dart is also used to run javascript code as a native citzen, but without flutter channels, and thanks to native_assets_cli, quickjs-dart could be integrated into any dart app (not flutter currently) with all platform support(except web). The integrated quickjs version is `2024-02-14`.

Have a try with `dart --enable-experiment=native-assets run example/example.dart`

## asynchronous

All interops with quickjs native code through `dart:ffi` run in a separated isolate, this could make sure js evaluation would not block the main isolate, also a different point from flutter_js.
```dart
final manager = await JsEngineManager.create();
final engine = await manager.createEngine('my-tag');
final result = await engine.eval('console.log("Hello~");');
print(result.stdout); // "Hello~"
await engine.dispose();
await manager.dispose();
```

Of course, quickjs-dart could aslo run in main isolate synchronously, just using different objects:
```dart
final manager = NativeEngineManager();
final engine = NativeJsEngine(name: 'my-tag');
final result = engine.eval('3-4');
print(result.value); // "-1"
engine.dispose();
manager.dispose();
```

## notify callback

If you want to receive data directly from js code, you need register a notify callback in Dart side:
```
const code = """
let scope = {
  send(obj) {
    _ffiNotify("_sendMsg", JSON.stringify(obj));
  }
};
scope.send({"key": $variable_in_dart});
""";
engine.eval(code); // receive message but do nothing.
engine.registerBridge('_sendMsg', (obj) {
  final val = obj['key']; // $variable_in_dart
});
engine.eval(code); // receive message call dart callback.
```
remember to use the builtin `_ffiNotify` in js world.

## builtin js functions

- console.log
- setTimeout
- \_ffiNotify
