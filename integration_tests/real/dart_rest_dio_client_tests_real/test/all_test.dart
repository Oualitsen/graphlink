import '../../dart_rest_client_tests_real/test/query_params_test.dart' as query_params;
import '../../dart_rest_client_tests_real/test/headers_test.dart' as headers;
import '../../dart_rest_client_tests_real/test/json_body_test.dart' as json_body;
import '../../dart_rest_client_tests_real/test/form_test.dart' as form;
import '../../dart_rest_client_tests_real/test/multipart_test.dart' as multipart;
import '../../dart_rest_client_tests_real/test/raw_upload_test.dart' as raw_upload;
import '../../dart_rest_client_tests_real/test/responses_test.dart' as responses;
import '../../dart_rest_client_tests_real/test/download_test.dart' as download;
import '../../dart_rest_client_tests_real/test/crud_flow_test.dart' as crud_flow;
import '../../dart_rest_client_tests_real/test/cache_test.dart' as cache;
import '../../dart_rest_client_tests_real/test/transport_test.dart' as transport;
import '../../dart_rest_client_tests_real/test/edge_cases_test.dart' as edge_cases;
import 'package:test/test.dart';

void main() {
  group('edge_cases', edge_cases.main);
  group('query_params', query_params.main);
  group('headers', headers.main);
  group('json_body', json_body.main);
  group('form', form.main);
  group('multipart', multipart.main);
  group('raw_upload', raw_upload.main);
  group('responses', responses.main);
  group('download', download.main);
  group('crud_flow', crud_flow.main);
  group('cache', cache.main);
  group('transport', transport.main);
}
