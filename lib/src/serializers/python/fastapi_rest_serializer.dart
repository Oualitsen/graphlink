import 'package:graphlink/src/serializers/python/python_rest_constants.dart';
import 'package:graphlink/src/serializers/python/python_rest_serializer.dart';

class FastapiRestSerializer extends PythonRestSerializer {
  FastapiRestSerializer(super.grammar, super.py, super.config);

  @override
  String get requestType => 'Request';

  @override
  String get responseType => 'Response';

  @override
  List<String> get requestImports => ['from starlette.requests import Request', 'from starlette.responses import Response'];

  @override
  String get domainJsonResponse => 'JSONResponse(body, status_code=status)';

  @override
  String get supportRuntime => pythonRestSupportStarlette;

  @override
  String get downloadRuntime => pythonRestDownloadStarlette;

  @override
  String get rawUploadRuntime => pythonRestUploadsRawStarlette;

  @override
  String get multipartUploadRuntime => pythonRestUploadsMultipartStarlette;
}
