package dev.graphlink.mappermock

import dev.graphlink.mappermock.generatedserver.mappers.UserEntityMapper
import dev.graphlink.mappermock.generatedserver.mappers.UserMapper
import dev.graphlink.mappermock.generatedserver.types.User
import dev.graphlink.mappermock.persistence.AddressEntity
import dev.graphlink.mappermock.persistence.UserEntity
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class MapperServerTest {
    private fun address(street: String) = AddressEntity().apply { this.street = street }

    private fun entity() = UserEntity().apply {
        id = "1"
        fullName = "Ada Lovelace"
        addresses = listOf(address("Main"), address("Side"))
        home = address("Home")
    }

    @Test
    fun externalSourceCopiesFieldsAndMapsListAndNestedValue() {
        val user = UserEntityMapper.toUser(entity(), defaultNick = "anon")
        assertEquals("1", user.id)
        assertEquals("Ada Lovelace", user.fullName)
        assertEquals(listOf("Main", "Side"), user.addresses.map { it.street })
        assertEquals("Home", user.home?.street)
    }

    @Test
    fun externalSourceNullTakesTheDefaultAndAPresentValueWins() {
        assertEquals("anon", UserEntityMapper.toUser(entity(), "anon").nick)
        val other = UserEntity().apply { id = "2"; fullName = "B"; nick = "bee" }
        val user = UserEntityMapper.toUser(other, "anon")
        assertEquals("bee", user.nick)
        assertNull(user.home)
        assertEquals(emptyList(), user.addresses)
    }

    @Test
    fun externalTargetIsBuiltWithNestedValues() {
        val back = UserMapper.toUserEntity(UserEntityMapper.toUser(entity(), "anon"))
        assertEquals("1", back.id)
        assertEquals("Ada Lovelace", back.fullName)
        assertEquals("anon", back.nick)
        assertEquals(listOf("Main", "Side"), back.addresses.map { it.street })
        assertEquals("Home", back.home?.street)
    }

    @Test
    fun externalTargetKeepsANullNestedValueNull() {
        val bare = UserEntity().apply { id = "3"; fullName = "C" }
        assertNull(UserMapper.toUserEntity(UserEntityMapper.toUser(bare, "n")).home)
    }

    @Test
    fun mapperStyleClassRenamesAFieldForOneTarget() {
        val summary = UserMapper.toUserSummary(UserEntityMapper.toUser(entity(), "anon"))
        assertEquals("1", summary.id)
        assertEquals("Ada Lovelace", summary.name)
    }

    @Test
    fun theGeneratedTypeHasNoInlineToMethod() {
        assertFailsWith<NoSuchMethodException> { User::class.java.getMethod("toUserSummary") }
    }
}
