package dev.graphlink.test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.interfaces.Attachment;
import dev.graphlink.test.generated.inputs.ListingFieldArgs;
import dev.graphlink.test.generated.inputs.ListingsFieldArgs;
import dev.graphlink.test.generated.inputs.SoloFieldArgs;
import dev.graphlink.test.generated.interfaces.Entity;
import dev.graphlink.test.generated.interfaces.Listing;
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

    @Test
    void anAliasKeepsBothTypesOfASharedFieldReadable() {
        assertEquals(6, ((Phone_IdSize) client.queries.fetchGadget("p1").getGadget()).getSize());
        assertEquals("15 inch", ((Laptop_IdSize) client.queries.fetchGadget("l1").getGadget()).getLaptopSize());
        assertNull(client.queries.fetchGadget("nope").getGadget());
        var gadgets = client.queries.fetchGadgets().getGadgets();
        assertInstanceOf(Phone_IdSize.class, gadgets.get(0));
        assertInstanceOf(Laptop_IdSize.class, gadgets.get(1));
    }

    @Test
    void aTypeInTwoUnionsDecodesThroughBoth() {
        assertInstanceOf(Photo.class, client.queries.shareable("ph1").getShareable());
        assertInstanceOf(Photo.class, client.queries.attachment("ph1").getAttachment());
        assertEquals("Pixel", ((Phone) client.queries.shareable("p1").getShareable()).getModel());
        assertNull(client.queries.shareable("nope").getShareable());
    }

    @Test
    void theArgumentReachesEveryImplementerAndEachKeepsItsOwnFields() {
        Listing album = client.queries.listing("al1", new ListingFieldArgs(2)).getListing();
        assertInstanceOf(Album.class, album);
        assertEquals(2020, ((Album) album).getYear());
        assertEquals(List.of(Photo.class, Video.class), album.getItems().stream().<Class<?>>map(Object::getClass).toList());
        Listing playlist = client.queries.listing("pl1", new ListingFieldArgs(5)).getListing();
        assertEquals(12, ((Playlist) playlist).getTracks());
        assertEquals(List.of(Video.class, Document.class), playlist.getItems().stream().<Class<?>>map(Object::getClass).toList());
    }

    @Test
    void aLimitOfZeroYieldsEmptyLists() {
        assertTrue(client.queries.listing("al1", new ListingFieldArgs(0)).getListing().getItems().isEmpty());
    }

    @Test
    void theInterfaceFieldReturnsTheOtherImplementerOrNull() {
        Listing summer = client.queries.listing("al1", new ListingFieldArgs(1)).getListing();
        assertEquals(12, ((Playlist) summer.getRelated()).getTracks());
        assertNull(client.queries.listing("al2", new ListingFieldArgs(1)).getListing().getRelated());
    }

    @Test
    void anUnknownListingIdDecodesNull() {
        assertNull(client.queries.listing("nope", new ListingFieldArgs(1)).getListing());
    }

    @Test
    void aListOfTheInterfaceDecodesEachImplementer() {
        List<Listing> listings = client.queries.listings(new ListingsFieldArgs(1)).getListings();
        assertEquals(List.of(Album.class, Playlist.class, Album.class), listings.stream().<Class<?>>map(Object::getClass).toList());
        assertEquals(List.of(1, 1, 1), listings.stream().map(l -> l.getItems().size()).toList());
    }

    @Test
    void aSingleMemberUnionDecodesToTheMember() {
        Object solo = client.queries.solo(new SoloFieldArgs(1)).getSolo();
        assertInstanceOf(Album.class, solo);
        assertEquals("Summer", ((Album) solo).getTitle());
    }

    @Test
    void idAndUrlAreReadableOnTheUnionItself() {
        List<Attachment> list = client.queries.attachments().getAttachments();
        assertEquals(List.of("ph1", "v1", "d1"), list.stream().map(Attachment::getId).toList());
        assertEquals(List.of("http://cdn/1.png", "http://cdn/1.mp4", "http://cdn/1.pdf"), list.stream().map(Attachment::getUrl).toList());
    }

    @Test
    void aSelectionThatSharesOnlySomeFieldsExposesJustThose() {
        assertEquals("ph1", client.queries.fetchPhotoParts("ph1").getAttachment().getId());
        assertEquals("v1", client.queries.fetchPhotoParts("v1").getAttachment().getId());
    }

    @Test
    void aUnionOfTwoTypesSharesOnlyId() {
        assertEquals("ph1", client.queries.shareable("ph1").getShareable().getId());
        assertEquals("p1", client.queries.shareable("p1").getShareable().getId());
    }

    @Test
    void theDirectQueryKeepsTheFullType() {
        Photo photo = client.queries.photo("ph1").getPhoto();
        assertEquals(List.of("ph1", "http://cdn/1.png", 640), List.of(photo.getId(), photo.getUrl(), photo.getWidth()));
        assertNull(client.queries.photo("nope").getPhoto());
    }

    @Test
    void aPartialSelectionOfTheSameTypeDoesNotReplaceIt() {
        assertEquals(640, client.queries.fetchPhotoWidth("ph1").getPhoto().getWidth());
        assertEquals("http://cdn/1.png", ((Photo_Url) client.queries.fetchPhotoUrl("ph1").getAttachment()).getUrl());
        assertInstanceOf(Video_Id.class, client.queries.fetchPhotoUrl("v1").getAttachment());
    }

    @Test
    void anInterfaceFragmentMixedWithConcreteOnes() {
        var results = client.queries.searchMixed("x").getSearch();
        assertEquals(List.of("user-1", "post-1"), results.stream().map(r -> r.getId()).toList());
        assertEquals("Alice Smith", ((UserResult_IdName) results.get(0)).getName());
        assertEquals("Hello World", ((PostResult) results.get(1)).getTitle());
    }

    private String nodeTitle() {
        return ((Article) client.queries.getCachedNode("a1").getGetCachedNode()).getTitle();
    }

    private int videoSeconds() {
        return ((Video) client.queries.getCachedAttachment("v1").getGetCachedAttachment()).getSeconds();
    }

    @Test
    void aCachedInterfaceResultIsServedFromTheCache() {
        assertEquals(nodeTitle(), nodeTitle());
    }

    @Test
    void invalidatingTheTagOfACachedInterfaceFetchesItAgain() {
        String before = nodeTitle();
        client.mutations.evictNodes();
        assertNotEquals(before, nodeTitle());
    }

    @Test
    void invalidatingTheTagOfACachedUnionFetchesItAgain() {
        int before = videoSeconds();
        assertEquals(before, videoSeconds());
        client.mutations.evictAttachments();
        assertNotEquals(before, videoSeconds());
    }

    @Test
    void invalidatingAnotherTagLeavesTheCachedUnionAlone() {
        int before = videoSeconds();
        client.mutations.evictNodes();
        assertEquals(before, videoSeconds());
    }
}
