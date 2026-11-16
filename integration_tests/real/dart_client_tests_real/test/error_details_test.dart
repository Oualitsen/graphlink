import 'package:test/test.dart';
import 'real_server_adapter.dart';

void main() {
  test('error carries message, path, locations and typed extensions', () async {
    final res = await newClient().queries.getUserOrErrors(id: 'missing');
    final e = res.errors!.single;
    expect(e.message, 'User not found: missing');
    expect(e.path, ['getUserOrErrors']);
    expect(e.locations!.first.line, 1);
    expect(e.extensions!['code'], 'NOT_FOUND');
    expect(e.extensions!['retryable'], false);
    final detail = e.extensions!['detail'] as Map<String, dynamic>;
    expect(detail['id'], 'missing');
    expect(detail['attempts'], 3);
  });

  test('partial data: ok is returned, bad is null, error path is the alias', () async {
    final res = await newClient().queries.partialAliased();
    expect(res.data!.ok.id, 'user-1');
    expect(res.data!.bad, isNull);
    expect(res.errors!.single.path, ['bad']);
  });
}
