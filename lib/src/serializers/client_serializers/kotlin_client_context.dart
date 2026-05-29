import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

class KotlinClientContext {
  final GLParser grammar;
  final KotlinCodeGenUtils codeGenUtils;
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
  final String svHandler;
  final String svFragmentMap;
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
  final String svEntry;
  final String svRemainingCount;
  final String svWrappedResponse;
  final String svPqVars;

  KotlinClientContext(this.grammar, this.codeGenUtils, this.gqlSerializer, this.serializer)
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
        svHandler = codeGenUtils.safeLocalVar('handler'),
        svFragmentMap = codeGenUtils.safeLocalVar('fragmentMap'),
        svMultipartAdapter = 'multipartAdapter',
        svAdapter = 'adapter',
        svStore = 'store',
        svEncoder = 'encoder',
        svDecoder = 'decoder',
        svFiles = codeGenUtils.safeLocalVar('files'),
        svFileMap = codeGenUtils.safeLocalVar('fileMap'),
        svOperationsMap = codeGenUtils.safeLocalVar('operationsMap'),
        svOperations = codeGenUtils.safeLocalVar('operations'),
        svMapJson = codeGenUtils.safeLocalVar('mapJson'),
        svEntry = codeGenUtils.safeLocalVar('entry'),
        svRemainingCount = codeGenUtils.safeLocalVar('remainingCount'),
        svWrappedResponse = codeGenUtils.safeLocalVar('wrappedResponse'),
        svPqVars = codeGenUtils.safeLocalVar('pqVars');
}
