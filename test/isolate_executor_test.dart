import 'dart:async';
import 'dart:io';

import 'package:isolate_executor/isolate_executor.dart';
import 'package:test/test.dart';

void main() {
  final projDir = Directory.current.uri.resolve("test/").resolve("test_package/");

  setUpAll(() async {
    await getDependencies(projDir);
  });

  test("Can run an Executable and get its return value", () async {
    final result =
        await IsolateExecutor.run(SimpleReturner({}), packageConfigURI: projDir.resolve(".packages"));
    expect(result, 1);
  });

  test("Logged messages are available through logger stream", () async {
    final msgs = [];
    await IsolateExecutor.run(SimpleReturner({}),
        logHandler: (msg) => msgs.add(msg), packageConfigURI: projDir.resolve(".packages"));
    expect(msgs, ["hello"]);
  });

  test("Send values to Executable and use them", () async {
    final result = await IsolateExecutor.run(Echo({'echo': 'hello'}), packageConfigURI: projDir.resolve(".packages"));
    expect(result, 'hello');
  });

  test("Run from another package", () async {
    final result = await IsolateExecutor.run(InPackage({}),
        packageConfigURI: projDir.resolve(".packages"), imports: ["package:test_package/lib.dart"]);

    expect(result, {"def": "default", "pos": "positionalArgs", "nam": "namedArgs", "con": "fromID"});
  });

  test("Can get messages thru stream", () async {
    var completers = [new Completer(), new Completer(), new Completer()];
    var futures = [completers[0].future, completers[1].future, completers[2].future];

    final result = await IsolateExecutor.run(Streamer({}), packageConfigURI: projDir.resolve(".packages"),
        eventHandler: (event) {
      completers.last.complete(event);
      completers.removeLast();
    });
    expect(result, 0);

    final completed = await Future.wait(futures);
    expect(completed.any((i) => i == 1), true);
    expect(completed.any((i) => i is Map && i["key"] == "value"), true);
    expect(completed.any((i) => i is Map && i["key1"] == "value1" && i["key2"] == "value2"), true);
  });

  test("Can instantiate types including in additionalContents", () async {
    final result = await IsolateExecutor.run(AdditionalContentsInstantiator({}),
        packageConfigURI: projDir.resolve(".packages"), additionalContents: """
class AdditionalContents { int get id => 10; }
    """);

    expect(result, 10);
  });

  test("If error is thrown, it is made available to consumer and the stack trace has been trimmed of script source", () async {
    try {
      await IsolateExecutor.run(Thrower({}), packageConfigURI: projDir.resolve(".packages"));
      fail('unreachable');
    } on StateError catch (e, st) {
      expect(e.toString(), contains("thrower-error"));
      expect(st.toString().contains("import"), false);
    }
  });
}

class SimpleReturner extends Executable {
  SimpleReturner(Map<String, dynamic> message) : super(message);

  @override
  Future<dynamic> execute() async {
    log("hello");
    return 1;
  }
}

class Echo extends Executable<String> {
  Echo(Map<String, dynamic> message)
      : echoMessage = message['echo'],
        super(message);

  final String echoMessage;

  @override
  Future<String> execute() async {
    return echoMessage;
  }
}

abstract class SomeObjectBaseClass {
  String get id;
}

class InPackage extends Executable<Map<String, String>> {
  InPackage(Map<String, dynamic> message) : super(message);

  @override
  Future<Map<String, String>> execute() async {
    SomeObjectBaseClass def = instanceOf("DefaultObject");
    SomeObjectBaseClass pos = instanceOf("PositionalArgumentsObject", positionalArguments: ["positionalArgs"]);
    SomeObjectBaseClass nam = instanceOf("NamedArgumentsObject", namedArguments: {#id: "namedArgs"});
    SomeObjectBaseClass con = instanceOf("NamedConstructorObject", constructorName: #fromID);
    return {"def": def.id, "pos": pos.id, "nam": nam.id, "con": con.id};
  }
}

class Streamer extends Executable {
  Streamer(Map<String, dynamic> message) : super(message);

  @override
  Future<dynamic> execute() async {
    send(1);
    send({"key": "value"});
    send({"key1": "value1", "key2": "value2"});
    return 0;
  }
}

class Thrower extends Executable {
  Thrower(Map<String, dynamic> message) : super(message);

  @override
  Future<dynamic> execute() async {
    throw StateError('thrower-error');
  }
}

class AdditionalContentsInstantiator extends Executable {
  AdditionalContentsInstantiator(Map<String, dynamic> message) : super(message);

  @override
  Future<dynamic> execute() async {
    final obj = instanceOf("AdditionalContents");
    return obj.id;
  }
}

Future<ProcessResult> getDependencies(Uri projectDir) async {
  final cmd = Platform.isWindows ? "pub.bat" : "pub";
  return Process.run(cmd, ["get"], workingDirectory: projectDir.toFilePath(windows: Platform.isWindows));
}
