import 'package:quickjs/src/native_js_engine.dart';
import 'package:test/test.dart';

const _module = """
function Page(options) {
  class _Page {
    constructor(options) {
      Object.assign(this, options)
    }

    setData(obj) {
      Object.assign(this.data, obj);
      console.log(JSON.stringify(obj));
      _ffiNotify('_onDataChanged', JSON.stringify(obj));
    }

    dismissDialog(cb) {
      let dlg = this.dialogs.pop();
      cb(dlg);
      dlg.dismiss?.();
    }

    showDialog(name, obj) {
      obj._name_ = name;
      if (!this.dialogs) this.dialogs = [];
      let dlg = this.dialogs;
      obj.key = dlg.length.toString();
      dlg.push(obj);
    }

    onClickNickname() {
      let items = [{
        text: this.options.lang === "en-us"? "Copy": "复制昵称",
        onClick() {
          console.log("copy nickname click!");
        },
      }];
      page.showDialog('name_card_select', {
        options: items,
      });
    }
  }
  return new _Page(options);
}
""";

const _code = """
let page = Page({
  data: {
    job: "Engineer",
    self: false,
    code: -1,
  },
  options: {
    lang: 'en-us',
    view: 'guest',
  },
  onLoad: function () {
    console.log("'onLoad' done!");
  },
  onClick: function() {
    this.setData({
      self: !this.data.self,
    })
  },
  sendMsg: function(n) {
    this.setData({
      code: this.data.code + n
    })
  }
});
""";

void main() {
  final manager = ManagerTester();
  final engine = NativeJsEngine(name: '<test_obj>',
      code: '$_module globalThis.Page=Page;');

  test('test scope evaluation', () {
    var result = engine.eval(_code);
    expect(result.stderr, null);

    final jobVal = engine.eval('with (page) {data.job}');
    expect(jobVal.stderr, null);
    expect(jobVal.value, 'Engineer');

    result = engine.eval('with (page) {onLoad()}');
    expect(result.stderr, null);
    expect(result.stdout, "'onLoad' done!\n");

    result = engine.eval('with (page) {data.self}');
    expect(result.stderr, null);
    expect(result.value, "false");
    result = engine.eval('with (page) {onClick();data.self}');
    expect(result.stderr, null);
    expect(result.stdout, '{"self":true}\n');
    expect(result.value, "true");
  });

  test('test bridge with an object', () {
    engine.bridgeNotifyObject('page');
    engine.registerNotify('_onDataChanged', (data) {
      expect(data['code'], 1);
    });

    final result = engine.eval('with (page) {sendMsg(2);}');
    expect(result.stderr, null);
    expect(result.stdout, '{"code":1}\n');
  });

  test('test eval after bridge', () {
    const errorStr = """ReferenceError: 'x' is not defined
    at <eval> (<test_obj>)
""";
    engine.registerNotify('_onDataChanged', null);

    final result = engine.eval('x');
    expect(result.stderr, '$errorStr\n');
  });

  tearDownAll(() {
    engine.dispose();
    manager.dispose();
  });
}
