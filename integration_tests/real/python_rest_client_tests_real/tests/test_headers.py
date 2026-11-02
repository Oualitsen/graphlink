from generated import Trace, RestError

from .support import RestTestCase, header


class HeaderArguments(RestTestCase):
    async def test_scalar_header_and_spread_input(self) -> None:
        e = await self.client.queries.e_headers(tenant="t-1", trace=Trace(trace_id="tr", span_id="sp"))
        self.assertEqual(header(e, "X-Tenant"), "t-1")
        self.assertEqual(header(e, "X-Trace-Id"), "tr")
        self.assertEqual(header(e, "X-Span-Id"), "sp")

    async def test_null_header_field_and_argument_are_not_sent(self) -> None:
        e = await self.client.queries.e_headers(tenant="t", trace=Trace(trace_id="tr"))
        self.assertIsNone(header(e, "X-Span-Id"))
        self.assertIsNone(header(e, "X-Opt"))
        self.assertIsNone(header(e, "X-Roles"))

    async def test_list_header_is_joined_with_commas(self) -> None:
        e = await self.client.queries.e_headers(tenant="t", roles=["admin", "ops"])
        self.assertEqual(header(e, "X-Roles"), "admin,ops")


class AcceptAndContentType(RestTestCase):
    async def test_accept_default_and_override(self) -> None:
        self.assertEqual(header(await self.client.queries.e_accept(), "accept"), "application/json")
        self.assertEqual(header(await self.client.queries.e_accept_override(), "accept"), "application/vnd.test+json")

    async def test_get_sends_no_content_type(self) -> None:
        self.assertIsNone((await self.client.queries.e_accept()).content_type)


class AdapterHeaders(RestTestCase):
    async def test_provider_is_consulted_for_every_request(self) -> None:
        calls = [0]

        async def provider():
            calls[0] += 1
            return {"X-Provider": f"call-{calls[0]}"}

        client = self.new_client(headers=provider)
        self.assertEqual(header(await client.queries.e_accept(), "X-Provider"), "call-1")
        self.assertEqual(header(await client.queries.e_accept(), "X-Provider"), "call-2")

    async def test_argument_header_wins_over_provider(self) -> None:
        client = self.new_client(headers=lambda: {"X-Tenant": "from-provider", "X-Other": "kept"})
        e = await client.queries.e_headers(tenant="from-arg")
        self.assertEqual(header(e, "X-Tenant"), "from-arg")
        self.assertEqual(header(e, "X-Other"), "kept")

    async def test_auth_through_provider_and_401_without(self) -> None:
        with self.assertRaises(RestError) as caught:
            await self.client.queries.auth_check()
        self.assertEqual(caught.exception.status, 401)
        self.assertEqual(caught.exception.headers["www-authenticate"], "Bearer")
        client = self.new_client(headers=lambda: {"Authorization": "Bearer secret"})
        who = await client.queries.auth_check(tenant="acme")
        self.assertEqual((who.user, who.tenant), ("ann", "acme"))
