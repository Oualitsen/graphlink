# Backend decorators decided on the IR

## Goal
Which decorator a backend emits, and on what, is decided on the IR and unit-tested there.
Serializers only render.

## Done
- `GLResolverBinding` (`parser_extensions/gl_grammar_resolver_binding_extension.dart`): kind
  (query, mutation, subscription, typeField) and wire name. `rootResolverBinding`,
  `typeFieldResolverBinding`.
- `TypeScriptCodeGenUtils.decorator()` and `decorators:` on `createMethod` / `createClass`.
  NestJS resolvers, field resolvers and REST controllers no longer glue `'@X(...)\n'` strings.
- Ariadne (FastAPI, Django) takes decorators from the binding.
- User `@glAnnotation` on NestJS and Ariadne: `TypeScriptAnnotationSerializer` and
  `PythonAnnotationSerializer` feed `convertAnnotationsToDecorators` (services, root fields,
  mappings, arguments). `decoratorImportsOf` collects the imports. For TypeScript and Python
  `glImport` is a verbatim import line.
- Generated output of the nestjs, fastapi and django integration servers is byte-identical
  before and after.

## Not done
- User annotations on generated types. TypeScript types are interfaces (no decorators); Python
  types are pydantic classes and could take class decorators.
- Express has no decorators.
- `python_openapi_serializer.dart` keeps its fixed `@router.get(...)` routes.
