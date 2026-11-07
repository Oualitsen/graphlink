import unittest

from generated import InnerInput, OnlyOne, Spelling, UserStatus

from .real_server import new_client


class RealTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    @property
    def q(self):
        return self.client.queries


class NamedFragments(RealTestCase):
    async def test_a_fragment_that_spreads_another_fragment(self) -> None:
        u = (await self.q.frag_nested(id="user-1")).get_user
        self.assertEqual((u.id, u.name), ("user-1", "Alice Smith"))
        self.assertIs(u.status, UserStatus.ACTIVE)

    async def test_one_fragment_reused_by_two_operations(self) -> None:
        ids = [u.id for u in (await self.q.frag_reuse_a()).list_users]
        self.assertTrue({"user-1", "user-2"} <= set(ids))
        one = (await self.q.frag_reuse_b(id="user-2")).get_user
        self.assertEqual((one.id, one.name), ("user-2", "Bob Jones"))
        self.assertIsNotNone(one.email)

    async def test_a_fragment_on_an_interface_next_to_an_inline_fragment(self) -> None:
        feed = (await self.q.frag_on_interface()).feed
        self.assertTrue(feed)
        self.assertTrue(all(e.id and e.created_by for e in feed))

    async def test_several_root_fields_sharing_one_fragment(self) -> None:
        r = await self.q.multi_root()
        self.assertEqual((r.first.name, r.second.name), ("Alice Smith", "Bob Jones"))
        self.assertTrue({"user-1", "user-2"} <= {u.id for u in r.all})


class Variables(RealTestCase):
    async def test_defaults_apply_when_the_variable_is_not_given(self) -> None:
        self.assertEqual(len((await self.q.vars_defaults()).search_users), 1)

    async def test_an_explicit_value_replaces_the_default(self) -> None:
        r = (await self.q.vars_defaults(name="Alice", limit=5)).search_users
        self.assertEqual([u.id for u in r], ["user-1"])

    async def test_list_nested_list_and_enum_variables(self) -> None:
        r = (await self.q.vars_lists(
            a=[1, 2], b=[1, None], c=[[1], [2, 3]], e=[Spelling.X_Y], f=[None, Spelling.V1],
        )).echo_args
        self.assertEqual((r.a, r.b, r.c), ([1, 2], [1, None], [[1], [2, 3]]))
        self.assertEqual((r.e, r.f), ([Spelling.X_Y], [None, Spelling.V1]))

    async def test_a_nullable_enum_variable(self) -> None:
        self.assertIs((await self.q.vars_enum(one=OnlyOne.ONLY)).echo_args.one, OnlyOne.ONLY)

    async def test_an_input_object_variable(self) -> None:
        r = (await self.q.vars_input(inner=InnerInput(n=4, label="x"))).echo_inner
        self.assertEqual((r.n, r.label), (4, "x"))

    async def test_nullable_versus_non_null_variables(self) -> None:
        given = (await self.q.vars_nullable(dollar="$d", quote="q")).echo_nasty_args
        self.assertEqual((given.dollar, given.quote), ("$d", "q"))
        left = (await self.q.vars_nullable(quote="q")).echo_nasty_args
        self.assertEqual((left.dollar, left.quote), (None, "q"))


class IncludeAndSkip(RealTestCase):
    async def test_with_variables(self) -> None:
        both = (await self.q.conditional_vars(with_email=True, skip_name=False)).get_user
        self.assertEqual((both.id, both.name, both.email), ("user-1", "Alice Smith", "alice@test.com"))
        neither = (await self.q.conditional_vars(with_email=False, skip_name=True)).get_user
        self.assertEqual((neither.id, neither.name, neither.email), ("user-1", None, None))

    async def test_with_literals(self) -> None:
        u = (await self.q.conditional_literals()).get_user
        self.assertEqual(u.name, "Alice Smith")
        self.assertIsNone(u.email)
        self.assertIs(u.status, UserStatus.ACTIVE)
        self.assertIsNone(u.priority)


class Aliases(RealTestCase):
    async def test_the_same_field_twice_with_different_arguments(self) -> None:
        r = await self.q.aliases_same_field()
        self.assertEqual((r.a.id, r.b.id), ("user-1", "user-2"))

    async def test_aliases_named_after_keywords(self) -> None:
        r = (await self.q.alias_keywords()).class_
        self.assertEqual((r.default, r.import_), ("Alice Smith", "user-1"))

    async def test_an_alias_with_the_name_of_another_field(self) -> None:
        self.assertEqual((await self.q.alias_equals_other_field()).get_user.name, "alice@test.com")


class CollidingOperationNames(RealTestCase):
    async def test_with_a_type(self) -> None:
        self.assertEqual((await self.q.user()).get_user.id, "user-1")
        self.assertEqual((await self.q.photo2()).photo.id, "ph1")

    async def test_with_a_keyword(self) -> None:
        self.assertTrue((await self.q.return_()).list_users)

    async def test_with_an_auto_generated_operation_the_custom_one_wins(self) -> None:
        self.assertEqual((await self.q.shelf()).shelf.id, "s1")

    async def test_with_a_generated_response_type_name(self) -> None:
        self.assertEqual((await self.q.get_user_response()).get_user.id, "user-1")


class FieldArguments(RealTestCase):
    async def test_literals(self) -> None:
        self.assertEqual(
            (await self.q.shelf_items()).shelf.items,
            ["tags=[a, b]", "kind=x__y", "filter={n=3, label=L}", "limit=5"],
        )

    async def test_variables(self) -> None:
        r = (await self.q.shelf_items_vars(
            tags=["t"], kind=Spelling.V1, filter=InnerInput(n=1, label="f", tags=None), limit=7,
        )).shelf
        self.assertEqual(r.items[0], "tags=[t]")
        self.assertEqual(r.items[1], "kind=v1")
        self.assertEqual(r.items[3], "limit=7")

    async def test_server_side_defaults(self) -> None:
        self.assertEqual((await self.q.shelf_items_defaults()).shelf.items[-1], "limit=2")


class LiteralArguments(RealTestCase):
    async def test_lists_nulls_and_enums(self) -> None:
        r = (await self.q.literal_lists()).echo_args
        self.assertEqual((r.a, r.b, r.c), ([1, 2, 3], [1, None], [[1], [2, 3]]))
        self.assertEqual((r.e, r.f, r.g), ([Spelling.A, Spelling.X_Y], [None, Spelling.V1], [Spelling.SNAKE_CASE_2]))
        self.assertIs(r.one, OnlyOne.ONLY)

    async def test_an_input_object(self) -> None:
        r = (await self.q.literal_input()).echo_input
        self.assertEqual((r.a, r.b, r.c), ([4], [None, 5], [[6]]))
        self.assertEqual((r.e, r.f, r.g), ([Spelling.B2], [None], [Spelling.A]))

    async def test_every_scalar_kind(self) -> None:
        r = (await self.q.literal_scalars()).echo_everything
        self.assertEqual((r.i, r.neg, r.big), (5, -3, 9))
        self.assertEqual((r.f, r.exp, r.b, r.bf), (2.5, 100.0, False, True))
        self.assertEqual((r.s, r.id), ("lit", "q"))
        self.assertIs(r.e, Spelling.V1)
        self.assertEqual((r.ints, r.nested), ([9], [[1]]))
        self.assertEqual((r.inner.n, r.inner.label), (2, "L"))
        self.assertIsNone(r.nothing)
        self.assertEqual(r.empty_list, [])
        self.assertIsNone(r.empty_obj.n)

    async def test_mixed_with_variables(self) -> None:
        r = (await self.q.literals_mixed(a=[8], one=OnlyOne.ONLY)).echo_args
        self.assertEqual((r.a, r.e, r.f), ([8], [Spelling.A, Spelling.B2], [Spelling.V1]))
        self.assertIs(r.one, OnlyOne.ONLY)
