import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

/// Bundles shared dependencies and pre-computed safe variable names for
/// [JavaClientSerializer] and its helper classes.
class JavaClientContext {
  final GLParser grammar;
  final JavaCodeGenUtils codeGenUtils;
  final GLGraphqlSerializer gqlSerializer;
  final GLSerializer serializer;

  final String svOperationName;
  final String svFragsValues;
  final String svQuery;
  final String svPayload;
  final String svVariables;
  final String svResponseText;
  final String svDecodedResponse;
  final String svPartialQueries;
  final String svResponseMap;
  final String svStaleData;
  final String svRemaining;
  final String svRawListener;
  final String svHandler;
  final String svFragmentMap;
  final String svTagLocks;
  final String svMultipartAdapter;
  final String svAdapter;
  final String svStore;
  final String svEncoder;
  final String svDecoder;
  final String svFiles;
  final String svFileMap;
  final String svOperationsMap;
  final String svOperations;
  final String svMapJson;

  JavaClientContext(this.grammar, this.codeGenUtils, this.gqlSerializer, this.serializer)
      : svOperationName = codeGenUtils.safeLocalVar('operationName'),
        svFragsValues = codeGenUtils.safeLocalVar('fragsValues'),
        svQuery = codeGenUtils.safeLocalVar('query'),
        svPayload = codeGenUtils.safeLocalVar('payload'),
        svVariables = codeGenUtils.safeLocalVar('variables'),
        svResponseText = codeGenUtils.safeLocalVar('responseText'),
        svDecodedResponse = codeGenUtils.safeLocalVar('decodedResponse'),
        svPartialQueries = codeGenUtils.safeLocalVar('partialQueries'),
        svResponseMap = codeGenUtils.safeLocalVar('responseMap'),
        svStaleData = codeGenUtils.safeLocalVar('staleData'),
        svRemaining = codeGenUtils.safeLocalVar('remaining'),
        svRawListener = codeGenUtils.safeLocalVar('rawListener'),
        svHandler = codeGenUtils.safeLocalVar('handler'),
        svFragmentMap = codeGenUtils.safeLocalVar('fragmentMap'),
        svTagLocks = codeGenUtils.safeLocalVar('tagLocks'),
        svMultipartAdapter = codeGenUtils.safeLocalVar('multipartAdapter'),
        svAdapter = codeGenUtils.safeLocalVar('adapter'),
        svStore = codeGenUtils.safeLocalVar('store'),
        svEncoder = codeGenUtils.safeLocalVar('encoder'),
        svDecoder = codeGenUtils.safeLocalVar('decoder'),
        svFiles = codeGenUtils.safeLocalVar('files'),
        svFileMap = codeGenUtils.safeLocalVar('fileMap'),
        svOperationsMap = codeGenUtils.safeLocalVar('operationsMap'),
        svOperations = codeGenUtils.safeLocalVar('operations'),
        svMapJson = codeGenUtils.safeLocalVar('mapJson');
}
