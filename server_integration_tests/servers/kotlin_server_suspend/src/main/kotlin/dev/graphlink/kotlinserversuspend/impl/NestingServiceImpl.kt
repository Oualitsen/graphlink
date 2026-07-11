package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.enums.Color
import dev.graphlink.kotlinserversuspend.generated.interfaces.Media
import dev.graphlink.kotlinserversuspend.generated.interfaces.Shape
import dev.graphlink.kotlinserversuspend.generated.services.NestingService
import dev.graphlink.kotlinserversuspend.generated.types.Box
import dev.graphlink.kotlinserversuspend.generated.types.Circle
import dev.graphlink.kotlinserversuspend.generated.types.Photo
import dev.graphlink.kotlinserversuspend.generated.types.Square
import dev.graphlink.kotlinserversuspend.generated.types.Video
import org.springframework.stereotype.Service

/** List-depth (1/2/3) × nullability × kind (type / interface / union / enum) resolvers. */
@Service
class NestingServiceImpl : NestingService {

    private fun box(id: String) = Box(id = id, label = "label-$id")
    private fun circle(id: String) = Circle(id = id, kind = "circle", radius = 1)
    private fun square(id: String) = Square(id = id, kind = "square", side = 2)
    private fun photo(id: String) = Photo(id = id, url = "https://x/$id.jpg", width = 640)
    private fun video(id: String) = Video(id = id, url = "https://x/$id.mp4", durationSec = 30)

    override suspend fun colors1(): List<Color> = listOf(Color.RED, Color.GREEN, Color.BLUE)

    override suspend fun colors2(): List<List<Color?>?>? = listOf(listOf(Color.RED), listOf(Color.GREEN, Color.BLUE))

    override suspend fun colors3(): List<List<List<Color>>> = listOf(listOf(listOf(Color.RED)))

    override suspend fun boxes1(): List<Box?>? = listOf(box("b1"), box("b2"))

    override suspend fun boxes2(): List<List<Box>> = listOf(listOf(box("b1")), listOf(box("b2")))

    override suspend fun boxes3(): List<List<List<Box?>?>?>? = listOf(listOf(listOf(box("b1"))))

    override suspend fun shapes1(): List<Shape> = listOf(circle("c1"), square("s1"))

    override suspend fun shapes2(): List<List<Shape?>?>? = listOf(listOf(circle("c1")), listOf(square("s1")))

    override suspend fun shapes3(): List<List<List<Shape>>> = listOf(listOf(listOf(circle("c1"), square("s1"))))

    override suspend fun media1(): List<Media> = listOf(photo("p1"), video("v1"))

    override suspend fun media2(): List<List<Media?>?>? = listOf(listOf(photo("p1")), listOf(video("v1")))

    override suspend fun media3(): List<List<List<Media>>> = listOf(listOf(listOf(photo("p1"), video("v1"))))
}
