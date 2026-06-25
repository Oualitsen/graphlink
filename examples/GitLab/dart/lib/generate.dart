import 'package:graphlink/src/main.dart' as graphlink;

Future<void> main(List<String> args) async {
  await graphlink.main(['--config', 'config.json']);
}
