import unittest

from generated import GraphLinkException, ListTeamsFieldArgs

from .fixtures import new_client, start_first


class InterceptTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_greet_intercepted_appends_the_run_before_marker(self) -> None:
        res = await self.client.queries.greet_intercepted(name="Ada")
        self.assertEqual(res.greet_intercepted.message, "Hello, Ada(runBefore)")

    async def test_greet_plain_is_not_intercepted(self) -> None:
        self.assertEqual((await self.client.queries.greet_plain(name="Ada")).greet_plain.message, "Hello, Ada")

    async def test_greeting_received_bakes_the_marker_into_every_emitted_greeting(self) -> None:
        event = await start_first(self.client.subscriptions.greeting_received())
        await self.client.mutations.send_greeting(name="Ada")
        self.assertEqual((await event).greeting_received.message, "Hello, Ada(runBefore)")

    async def test_team_members_intercepted_mapping_allows_role_auth(self) -> None:
        res = await self.client.queries.list_teams(field_args=ListTeamsFieldArgs(members_role="auth"))
        self.assertEqual({m.name for m in res.list_teams[0].members}, {"Ada", "Grace"})

    async def test_team_members_intercepted_mapping_denies_any_other_role(self) -> None:
        with self.assertRaises(GraphLinkException):
            await self.client.queries.list_teams(field_args=ListTeamsFieldArgs(members_role="wrong"))
