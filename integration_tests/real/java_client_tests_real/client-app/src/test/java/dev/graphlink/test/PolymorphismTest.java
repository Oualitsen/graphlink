package dev.graphlink.test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.interfaces.Attachment;
import dev.graphlink.test.generated.interfaces.Entity;
import dev.graphlink.test.generated.types.*;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class PolymorphismTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    @Test
    void aUnionMemberPerId() {
        Attachment photo = client.queries.attachment("ph1").getAttachment();
        Attachment video = client.queries.attachment("v1").getAttachment();
        Attachment document = client.queries.attachment("d1").getAttachment();
        assertInstanceOf(Photo.class, photo);
        assertEquals(640, ((Photo) photo).getWidth());
        assertEquals(30, ((Video) video).getSeconds());
        assertEquals(12, ((Document) document).getPages());
    }

    @Test
    void aNullableUnionDecodesNull() {
        assertNull(client.queries.attachment("nope").getAttachment());
    }

    @Test
    void aListOfUnionMembers() {
        List<Attachment> list = client.queries.attachments().getAttachments();
        assertInstanceOf(Photo.class, list.get(0));
        assertInstanceOf(Video.class, list.get(1));
        assertInstanceOf(Document.class, list.get(2));
    }

    @Test
    void nullElementsInAListOfUnions() {
        List<Attachment> list = client.queries.attachmentsNullable().getAttachmentsNullable();
        assertEquals(3, list.size());
        assertInstanceOf(Photo.class, list.get(0));
        assertNull(list.get(1));
        assertInstanceOf(Document.class, list.get(2));
    }

    @Test
    void aUnionReturnedByAMutation() {
        assertInstanceOf(Photo.class, client.mutations.addAttachment("a1", "u", "photo").getAddAttachment());
        assertInstanceOf(Video.class, client.mutations.addAttachment("a1", "u", "video").getAddAttachment());
        assertInstanceOf(Document.class, client.mutations.addAttachment("a1", "u", "document").getAddAttachment());
    }

    @Test
    void aServerErrorOnAUnionMutationThrows() {
        assertThrows(RuntimeException.class, () -> client.mutations.addAttachment("a1", "u", "bogus"));
    }

    @Test
    void aListOfAnInterfaceImplementingAnotherInterface() {
        List<Entity> feed = client.queries.feed().getFeed();
        assertInstanceOf(Article.class, feed.get(0));
        assertInstanceOf(Comment.class, feed.get(1));
        assertInstanceOf(Article.class, feed.get(2));
        assertInstanceOf(Comment.class, feed.get(3));
        assertEquals(List.of("alice", "bob", "bob", "alice"), feed.stream().map(Entity::getCreatedBy).toList());
    }

    @Test
    void aNullableInterfaceReturnsEachImplementationOrNull() {
        assertInstanceOf(Article.class, client.queries.node("a1").getNode());
        assertInstanceOf(Comment.class, client.queries.node("c1").getNode());
        assertNull(client.queries.node("zzz").getNode());
    }

    @Test
    void aUnionFieldAndAListOfUnionsInsideAnObject() {
        Article article = client.queries.article("a1").getArticle();
        assertInstanceOf(Photo.class, article.getCover());
        assertEquals(3, article.getAttachments().size());
        assertInstanceOf(Photo.class, article.getAttachments().get(0));
        assertInstanceOf(Video.class, article.getAttachments().get(1));
        assertInstanceOf(Document.class, article.getAttachments().get(2));
    }

    @Test
    void nullPolymorphicFields() {
        Article article = client.queries.article("a2").getArticle();
        assertNull(article.getCover());
        assertTrue(article.getAttachments().isEmpty());
        assertNull(article.getRelated());
    }

    @Test
    void nullElementsInAListOfInterfaces() {
        List<Entity> related = client.queries.article("a1").getArticle().getRelated();
        assertEquals(2, related.size());
        assertInstanceOf(Comment.class, related.get(0));
        assertNull(related.get(1));
    }

    @Test
    void anInterfaceFieldPointingBackAtAnImplementer() {
        Entity reply = client.queries.feed().getFeed().get(3);
        assertInstanceOf(Comment.class, reply);
        Entity parent = ((Comment) reply).getParent();
        assertInstanceOf(Article.class, parent);
        assertEquals("Hello", ((Article) parent).getTitle());
    }

    @Test
    void anUnknownArticleIsAnError() {
        assertThrows(RuntimeException.class, () -> client.queries.article("zzz"));
    }

    @Test
    void capturedErrorsOnAUnionOperation() {
        AttachmentOrErrorsFullResponse ok = client.queries.attachmentOrErrors("ph1");
        assertNull(ok.getErrors());
        assertInstanceOf(Photo.class, ok.getData().getAttachmentOrErrors());
        AttachmentOrErrorsFullResponse failed = client.queries.attachmentOrErrors("boom");
        assertNull(failed.getData().getAttachmentOrErrors());
        assertFalse(failed.getErrors().get(0).getMessage().isEmpty());
    }

    @Test
    void aCachedUnionOperationDecodesOnEveryCall() {
        Attachment first = client.queries.getCachedAttachment("v1").getGetCachedAttachment();
        Attachment second = client.queries.getCachedAttachment("v1").getGetCachedAttachment();
        assertInstanceOf(Video.class, first);
        assertInstanceOf(Video.class, second);
    }

    @Test
    void inlineFragmentsOnEveryMemberOfAUnion() {
        Attachment photo = client.queries.fetchAttachment("ph1").getAttachment();
        Attachment video = client.queries.fetchAttachment("v1").getAttachment();
        Attachment document = client.queries.fetchAttachment("d1").getAttachment();
        assertEquals(640, ((Photo) photo).getWidth());
        assertEquals(30, ((Video) video).getSeconds());
        assertEquals(12, ((Document) document).getPages());
        assertNull(client.queries.fetchAttachment("nope").getAttachment());
    }

    @Test
    void oneFragmentSharedByTwoRootFields() {
        FetchArticleAndAttachmentResponse res = client.queries.fetchArticleAndAttachment("a1", "v1");
        assertEquals("ph1", res.getArticle().getCover().getId());
        assertEquals("v1", res.getAttachment().getId());
        assertEquals(30, ((Video_IdSeconds) res.getAttachment()).getSeconds());
    }

    @Test
    void anInterfaceSelectionWithInlineFragmentsAndASharedFragment() {
        List<? extends Object> feed = client.queries.fetchFeed().getFeed();
        assertEquals(4, feed.size());
        Article_AttachmentsCoverCreatedBy_pztuu6 article = (Article_AttachmentsCoverCreatedBy_pztuu6) feed.get(0);
        assertEquals("Hello", article.getTitle());
        assertEquals("http://cdn/1.png", ((Photo_IdUrl) article.getCover()).getUrl());
        assertEquals(List.of("ph1", "v1", "d1"), article.getAttachments().stream().map(a -> a.getId()).toList());
        assertEquals("Nice", ((Comment) feed.get(1)).getText());
        assertNull(((Article_AttachmentsCoverCreatedBy_pztuu6) feed.get(2)).getCover());
    }

    @Test
    void anInterfaceSelectionThatNamesOnlySomeImplementers() {
        Article_CreatedByIdTitle article = (Article_CreatedByIdTitle) client.queries.fetchNode("a1").getNode();
        assertEquals("Hello", article.getTitle());
        assertEquals("alice", article.getCreatedBy());
        Comment_CreatedById comment = (Comment_CreatedById) client.queries.fetchNode("c1").getNode();
        assertEquals("bob", comment.getCreatedBy());
        assertNull(client.queries.fetchNode("nope").getNode());
    }

    @Test
    void twoQueriesSelectDifferentShapesOfTheSameUnion() {
        Photo photo = (Photo) client.queries.fetchPhotoParts("ph1").getAttachment();
        assertEquals(640, photo.getWidth());
        assertEquals("http://cdn/1.png", photo.getUrl());
        assertEquals("v1", ((Video_Id) client.queries.fetchPhotoParts("v1").getAttachment()).getId());
        assertEquals(640, ((Photo) client.queries.fetchAttachment("ph1").getAttachment()).getWidth());
    }
}
