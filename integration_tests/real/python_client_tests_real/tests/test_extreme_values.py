import math
import unittest

from generated import EverythingInput

from .test_literals import RealTestCase


class ExtremeVariableValues(RealTestCase):
    async def echo(self, **fields):
        return (await self.client.queries.echo_everything(input=EverythingInput(**fields))).echo_everything

    async def test_int_at_both_32_bit_limits(self) -> None:
        r = await self.echo(i=2147483647, neg=-2147483648)
        self.assertEqual((r.i, r.neg), (2147483647, -2147483648))

    async def test_float_at_1e308_and_negative_zero(self) -> None:
        r = await self.echo(f=1e308, exp=-0.0)
        self.assertEqual(r.f, 1e308)
        self.assertEqual(math.copysign(1.0, r.exp), -1.0)

    async def test_a_string_with_a_nul_character(self) -> None:
        self.assertEqual((await self.echo(s="a\u0000b")).s, "a\u0000b")

    async def test_a_string_with_lone_surrogates(self) -> None:
        sent = "x\ud800y\udc00z"
        self.assertEqual((await self.echo(s=sent)).s, sent)


if __name__ == "__main__":
    unittest.main()
