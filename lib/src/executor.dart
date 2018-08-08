import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:isolate_executor/src/executable.dart';
import 'package:isolate_executor/src/source_generator.dart';

class IsolateExecutor<U> {
  IsolateExecutor(this.generator, {this.packageConfigURI, Map<String, dynamic> message}) : this.message = message ?? {};

  final SourceGenerator generator;
  final Map<String, dynamic> message;
  final Uri packageConfigURI;
  final Completer completer = new Completer();

  Stream<dynamic> get events => _eventListener.stream;

  Stream<String> get console => _logListener.stream;

  final StreamController<String> _logListener = new StreamController<String>();
  final StreamController<dynamic> _eventListener = new StreamController<dynamic>();

  Future<U> execute() async {
    if (packageConfigURI != null && !(new File.fromUri(packageConfigURI).existsSync())) {
      throw new StateError("Package file '$packageConfigURI' not found. Run 'pub get' and retry.");
    }

    final scriptSource = Uri.encodeComponent(await generator.scriptSource);

    var onErrorPort = new ReceivePort()
      ..listen((err) async {
        if (err is List) {
          final stack = new StackTrace.fromString(err.last.replaceAll(scriptSource, ""));

          completer.completeError(new StateError(err.first), stack);
        } else {
          completer.completeError(err);
        }
      });

    var controlPort = new ReceivePort()
      ..listen((results) {
        if (results is Map && results.length == 1) {
          if (results.containsKey("_result")) {
            completer.complete(results['_result']);
            return;
          } else if (results.containsKey("_line_")) {
            _logListener.add(results["_line_"]);
            return;
          }
        }
        _eventListener.add(results);
      });

    try {
      message["_sendPort"] = controlPort.sendPort;

      final dataUri = Uri.parse("data:application/dart;charset=utf-8,${scriptSource}");
      if (packageConfigURI != null) {
        await Isolate.spawnUri(dataUri, [], message,
            errorsAreFatal: true, onError: onErrorPort.sendPort, packageConfig: packageConfigURI);
      } else {
        await Isolate.spawnUri(dataUri, [], message,
            errorsAreFatal: true, onError: onErrorPort.sendPort, automaticPackageResolution: true);
      }

      return await completer.future;
    } finally {
      onErrorPort.close();
      controlPort.close();
      _eventListener.close();
      _logListener.close();
    }
  }

  static Future<T> run<T>(Executable<T> executable,
      {Uri packageConfigURI,
      List<String> imports,
      String additionalContents,
      void eventHandler(dynamic event),
      void logHandler(String line),
      List<Type> additionalTypes}) async {
    final source = new SourceGenerator(executable.runtimeType, imports: imports, additionalContents: additionalContents, additionalTypes: additionalTypes);
    var executor = new IsolateExecutor<T>(source, packageConfigURI: packageConfigURI, message: executable.message);

    if (eventHandler != null) {
      executor.events.listen(eventHandler);
    }

    if (logHandler != null) {
      executor.console.listen(logHandler);
    }

    return executor.execute();
  }
}
