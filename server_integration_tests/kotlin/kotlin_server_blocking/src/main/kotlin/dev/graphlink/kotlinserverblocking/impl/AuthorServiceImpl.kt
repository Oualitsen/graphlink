package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.AuthorService
import dev.graphlink.kotlinserverblocking.generated.types.Author
import org.springframework.stereotype.Service

@Service
class AuthorServiceImpl : AuthorService {
    override fun getAuthor(id: String): Author? = Data.authors.firstOrNull { it.id == id }

    override fun listAuthors(): List<Author> = Data.authors.toList()
}
