import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';
import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:isolate_executor/src/executable.dart';
import 'package:pub_semver/pub_semver.dart';

class SourceGenerator {
  SourceGenerator(this.executableType,
      {this.imports, this.additionalContents, this.additionalTypes});

  Type executableType;

  String get typeName =>
      MirrorSystem.getName(reflectType(executableType).simpleName);
  final List<String> imports;
  final String additionalContents;
  final List<Type> additionalTypes;

  Future<String> get scriptSource async {
    final typeSource = (await _getClass(executableType)).toSource();
    var builder = new StringBuffer();

    builder.writeln("import 'dart:async';");
    builder.writeln("import 'dart:isolate';");
    builder.writeln("import 'dart:mirrors';");
    imports?.forEach((import) {
      builder.writeln("import '$import';");
    });
    builder.writeln("""
Future main (List<String> args, Map<String, dynamic> message) async {
  final sendPort = message['_sendPort'];
  final executable = new $typeName(message);
  final result = await executable.execute();
  sendPort.send({"_result": result});
}
    """);
    builder.writeln(typeSource);

    builder.writeln((await _getClass(Executable)).toSource());
    for (var type in additionalTypes ?? []) {
      final source = await _getClass(type);
      builder.writeln(source.toSource());
    }

    if (additionalContents != null) {
      builder.writeln(additionalContents);
    }

    return builder.toString();
  }

  static Future<ClassDeclaration> _getClass(Type type) async {
    final uri =
        await Isolate.resolvePackageUri(reflectClass(type).location.sourceUri);
    final fileUnit = parseFile(
        path: uri.toFilePath(windows: Platform.isWindows),
        featureSet: FeatureSet.fromEnableFlags2(
            flags: [], sdkLanguageVersion: Version(2, 8, 0)));
    final typeName = MirrorSystem.getName(reflectClass(type).simpleName);

    return fileUnit.unit.declarations
        .where((u) => u is ClassDeclaration)
        .map((cu) => cu as ClassDeclaration)
        .firstWhere((classDecl) => classDecl.name.name == typeName);
  }
}
