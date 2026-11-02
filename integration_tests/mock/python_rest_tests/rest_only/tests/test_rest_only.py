import json
import unittest

from generated import GraphLinkClient, RestResponse


class RestOnlyClient(unittest.IsolatedAsyncioTestCase):
    async def test_a_schema_with_only_rest_operations_needs_no_graphql_adapter(self) -> None:
        async def adapter(request):
            return RestResponse.from_text(200, json.dumps({"id": "p1", "name": "Pen"}))

        client = GraphLinkClient(rest_adapter=adapter)
        product = await client.queries.product(id="p1")
        self.assertEqual(product.name, "Pen")
        self.assertFalse(hasattr(client.queries, "ping"))
