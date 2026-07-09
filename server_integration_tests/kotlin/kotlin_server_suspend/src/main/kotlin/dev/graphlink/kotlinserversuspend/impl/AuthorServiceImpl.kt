package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.AuthorService
import dev.graphlink.kotlinserversuspend.generated.types.Author
import org.springframework.stereotype.Service

@Service
class AuthorServiceImpl : AuthorService {
    override suspend fun getAuthor(id: String): Author? = Data.authors.firstOrNull { it.id == id }

    override suspend fun listAuthors(): List<Author> = Data.authors.toList()
}
