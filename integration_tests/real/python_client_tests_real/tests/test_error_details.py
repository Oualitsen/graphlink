import unittest

from .real_server import new_client


class ErrorDetailsTest(unittest.IsolatedAsyncioTestCase):
    async def test_error_carries_message_path_locations_and_typed_extensions(self) -> None:
        res = await new_client().queries.get_user_or_errors(id="missing")
        self.assertEqual(len(res.errors), 1)
        e = res.errors[0]
        self.assertEqual(e.message, "User not found: missing")
        self.assertEqual(e.path, ["getUserOrErrors"])
        self.assertEqual(e.locations[0].line, 1)
        self.assertEqual(e.extensions["code"], "NOT_FOUND")
        self.assertIs(e.extensions["retryable"], False)
        self.assertEqual(e.extensions["detail"], {"id": "missing", "attempts": 3})

    async def test_partial_data_ok_is_returned_bad_is_null_and_the_error_path_is_the_alias(self) -> None:
        res = await new_client().queries.partial_aliased()
        self.assertEqual(res.data.ok.id, "user-1")
        self.assertIsNone(res.data.bad)
        self.assertEqual(len(res.errors), 1)
        self.assertEqual(res.errors[0].path, ["bad"])
