import 'package:graphlink/src/serializers/python/python_rest_constants.dart';
import 'package:graphlink/src/serializers/python/python_rest_serializer.dart';

class DjangoRestSerializer extends PythonRestSerializer {
  DjangoRestSerializer(super.grammar, super.py, super.config);

  @override
  String get requestType => 'HttpRequest';

  @override
  String get responseType => 'HttpResponse';

  @override
  List<String> get requestImports => ['from django.http import HttpRequest, HttpResponse'];

  @override
  String get supportRuntime => pythonRestSupportDjango;

  @override
  String get downloadRuntime => pythonRestDownloadDjango;

  @override
  String get rawUploadRuntime => pythonRestUploadsRawDjango;

  @override
  String get multipartUploadRuntime => pythonRestUploadsMultipartDjango;
}
