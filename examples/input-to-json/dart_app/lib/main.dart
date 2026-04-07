

import 'generated/client/graph_link_client.dart';

const _endpoint = 'http://localhost:8080/graphql';

void main() async {
   GraphLinkClient.withHttp(url: _endpoint);
}
