import 'package:test_package/src/src.dart';
export 'package:test_package/src/src.dart';

String libFunction() => "libFunction";

class DefaultObject implements SomeObjectBaseClass {
  String get id => "default";
}

class PositionalArgumentsObject implements SomeObjectBaseClass {
  PositionalArgumentsObject(this.id);
  String id;
}

class NamedArgumentsObject implements SomeObjectBaseClass {
  NamedArgumentsObject({this.id});

  String id;
}

class NamedConstructorObject implements SomeObjectBaseClass {
  NamedConstructorObject.fromID();
  String get id => "fromID";
}