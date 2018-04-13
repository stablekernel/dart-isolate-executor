import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

abstract class Executable {
  Executable(Map<String, dynamic> message) : _sendPort = message["_sendPort"];

  Future<dynamic> execute();

  SendPort _sendPort;

  dynamic instanceOf(String typeName,
      {List positionalArguments: const [], Map<Symbol, dynamic> namedArguments, Symbol constructorName}) {
    ClassMirror typeMirror = currentMirrorSystem().isolate.rootLibrary.declarations[new Symbol(typeName)];
    if (typeMirror == null) {
      typeMirror = currentMirrorSystem()
          .libraries
          .values
          .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
          .expand((lib) => lib.declarations.values)
          .firstWhere((decl) => decl is ClassMirror && MirrorSystem.getName(decl.simpleName) == typeName,
              orElse: () => throw new ArgumentError("Unknown type '$typeName'. Did you forget to import it?"));
    }

    return typeMirror.newInstance(constructorName ?? const Symbol(""), positionalArguments, namedArguments).reflectee;
  }

  void send(dynamic message) {
    _sendPort.send(message);
  }

  void log(String message) {
    _sendPort.send({"_line_": message});
  }
}
