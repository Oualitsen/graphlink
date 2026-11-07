import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';

class JavaAccessorSerializer {
  final JavaSerializer _owner;
  const JavaAccessorSerializer(this._owner);

  String generateContructor(String name, List<GLField> fields, String? modifier, GLToken context,
      {bool checkForNulls = false, bool isTypeField = false}) {
    String nullCheck = "";
    if (checkForNulls) {
      var checkingFields = fields
          .where((e) => !e.type.nullable && e.initialValue == null && !_owner.isPrimitiveType(e.type))
          .map((e) => "Objects.requireNonNull(${e.codeName});")
          .toList();

      if (checkingFields.isNotEmpty) {
        nullCheck = serializeListText(checkingFields, join: "\n", withParenthesis: false);
        context.addImport(JavaImports.objects);
      }
    }

    if (fields.isNotEmpty) {
      // Add Arrays import if any field has a list-type default value.
      final hasListDefault = fields.any((e) => !isTypeField && e.initialValue != null && e.type.isList);
      if (hasListDefault) {
        context.addImport(JavaImports.arrays);
      }
    }
    return _owner.codeGenUtils.createMethod(
      returnType: modifier,
      methodName: name,
      arguments: fields.map((e) => _owner.serializeArgumentField(e, isTypeField: isTypeField)).toList(),
      statements: [
        if (nullCheck.isNotEmpty) nullCheck,
        ...fields.map((e) {
          if (!isTypeField && e.initialValue != null) {
            final lit = _owner.serializeDefaultLiteral(e.type, e.initialValue);
            return "this.${e.codeName} = ${e.codeName} != null ? ${e.codeName} : $lit;";
          }
          return "this.${e.codeName} = ${e.codeName};";
        }),
      ],
    );
  }

  String generateBuilder(String name, List<GLField> fields, bool forInput) {
    if (fields.isEmpty) {
      return "";
    }

    var buffer = StringBuffer();
    buffer.writeln(_owner.codeGenUtils.createMethod(
      returnType: "public static Builder",
      methodName: "builder",
      statements: ['return new Builder();'],
    ));

    buffer.writeln();
    buffer.writeln(_owner.codeGenUtils.createClass(staticClass: true, className: 'Builder', statements: [
      ...fields.map((field) {
        final annotation = _owner.isPrimitiveType(field.type) ? null : _owner.getJSpecifyAnnoation(field);
        final copy = GLField(name: field.name, type: field.type, arguments: field.arguments, directives: [])..codeName = field.codeName;
        final serialized = _owner.serializeField(copy, false, !forInput);
        return annotation != null ? '$annotation\n$serialized' : serialized;
      }),
      "",
      ...fields.map((e) {
        final annotation = _owner.isPrimitiveType(e.type) ? null : _owner.getJSpecifyAnnoation(e);
        return _owner.codeGenUtils.createMethod(
            returnType: 'public Builder',
            methodName: e.codeName,
            arguments: ['${annotation != null ? "$annotation " : ""}${_owner.serializeArgumentField(e)}'],
            statements: ['this.${e.codeName} = ${e.codeName};', 'return this;']);
      }),
      "",
      _owner.codeGenUtils.createMethod(
          returnType: 'public $name', methodName: 'build', statements: ['return new $name(${fields.map((e) => e.codeName).join(", ")});']),
    ]));

    return buffer.toString();
  }

  String serializeGetter(GLField field, GLTokenWithFields context, {bool checkForNulls = false, bool isTypeField = false, bool isOverride = false}) {
    if (checkForNulls) {
      context.addImport(JavaImports.objects);
    }
    var returnType = _owner.serializeType(field.type);
    // Java's override rules require a primitive return type to match the
    // superinterface's exactly — a non-null `Boolean!` narrowing a nullable
    // `Boolean` produces a primitive `boolean` getter that neither compiles
    // against nor satisfies a `Boolean`-returning interface method (and would
    // wrongly rename to `isAlive`). Reference-type narrowing (including list
    // element types, e.g. `[Lion!]!` narrowing `[Animal!]!`) is legal Java
    // covariance and must NOT be rewritten here — for lists that covariance is
    // made to type-check by widening the *interface's own* declaration to
    // `List<? extends X>` (see wildcardListReturnType), not by changing the
    // implementer's getter.
    final interfaceField = isOverride && context is GLTypeDefinition ? context.getInterfaceField(field) : null;
    if (interfaceField != null && !interfaceField.type.isList) {
      final interfaceType = _owner.serializeType(interfaceField.type);
      if (javaPrimitives.contains(returnType) && !javaPrimitives.contains(interfaceType)) {
        returnType = interfaceType;
      }
    }
    var jspecifyAnnotation = _owner.isPrimitiveType(field.type) ? null : _owner.getJSpecifyAnnoation(field);
    var result = _owner.codeGenUtils.createMethod(
        returnType: "public ${returnType}",
        methodName: _owner.getterName(context, field.name.token),
        statements: [
          if (checkForNulls && !field.type.nullable && !_owner.isPrimitiveType(field.type)) 'Objects.requireNonNull(${field.codeName});',
          'return ${field.codeName};'
        ]);
    var buffer = StringBuffer();
    if (isOverride) {
      buffer.writeln("@Override");
    }
    if (jspecifyAnnotation != null) {
      buffer.writeln(jspecifyAnnotation);
    }
    buffer.write(result);
    return buffer.toString();
  }

  String _setterName(String propertyName) {
    return _accessorName(propertyName, true, false);
  }

  String _accessorName(String name, bool setter, bool isBoolean) => JavaSerializer.accessorName(name, setter: setter, isBoolean: isBoolean);

  String serializeSetter(GLField field, GLToken context, {bool checkForNulls = false}) {
    if (checkForNulls) {
      context.addImport(JavaImports.objects);
    }
    final annotation = _owner.isPrimitiveType(field.type) ? null : _owner.getJSpecifyAnnoation(field);
    return _owner.codeGenUtils.createMethod(returnType: 'public void', methodName: _setterName(field.codeName), arguments: [
      '${annotation != null ? "$annotation " : ""}${_owner.serializeArgumentField(field)}'
    ], statements: [
      if (checkForNulls && !field.type.nullable && !_owner.isPrimitiveType(field.type)) 'Objects.requireNonNull(${field.codeName});',
      "this.${field.codeName} = ${field.codeName};"
    ]);
  }
}
