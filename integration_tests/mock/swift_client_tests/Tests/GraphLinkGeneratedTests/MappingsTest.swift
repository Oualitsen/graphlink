import Foundation
import XCTest
@testable import GraphLinkGenerated

final class MappingsTest: XCTestCase {

    let article = MappedArticle(id: "a1", title: "Hello", body: "Body text", views: 7)
    let unviewed = MappedArticle(id: "a2", title: "Quiet", body: "No readers")

    // ── Type with several targets ─────────────────────────────────────────────

    func testToMappedArticleSummaryRenamesTitleToHeadline() {
        let summary = article.toMappedArticleSummary()
        XCTAssertEqual(summary.id, "a1")
        XCTAssertEqual(summary.headline, "Hello")
    }

    func testToMappedArticleCardRenamesTitleToNameAndKeepsViews() {
        let card = article.toMappedArticleCard(defaultViews: 99)
        XCTAssertEqual(card.id, "a1")
        XCTAssertEqual(card.name, "Hello")
        XCTAssertEqual(card.views, 7)
    }

    func testToMappedArticleCardUsesDefaultViewsWhenViewsIsNil() {
        let card = unviewed.toMappedArticleCard(defaultViews: 99)
        XCTAssertEqual(card.name, "Quiet")
        XCTAssertEqual(card.views, 99)
    }

    func testToMappedArticleUpdateInputKeepsTitleAndTakesStatus() {
        let update = article.toMappedArticleUpdateInput(status: "PUBLISHED")
        XCTAssertEqual(update.id, "a1")
        XCTAssertEqual(update.title, "Hello")
        XCTAssertEqual(update.body, "Body text")
        XCTAssertEqual(update.status, "PUBLISHED")
    }

    // ── Input with several targets ────────────────────────────────────────────

    let draft = MappedArticleDraftInput(title: "Draft", body: "Text", views: 3)
    let bare = MappedArticleDraftInput(title: "Bare", body: "Nothing")

    func testToMappedArticleCopiesTheFieldsAndTakesId() {
        let mapped = draft.toMappedArticle(id: "d1")
        XCTAssertEqual(mapped.id, "d1")
        XCTAssertEqual(mapped.title, "Draft")
        XCTAssertEqual(mapped.body, "Text")
        XCTAssertEqual(mapped.views, 3)
    }

    func testToMappedArticleKeepsANilViews() {
        XCTAssertNil(bare.toMappedArticle(id: "d2").views)
    }

    func testToMappedArticleUpdateInputTakesIdAndStatus() {
        let update = draft.toMappedArticleUpdateInput(id: "d1", status: "DRAFT")
        XCTAssertEqual(update.id, "d1")
        XCTAssertEqual(update.title, "Draft")
        XCTAssertEqual(update.body, "Text")
        XCTAssertEqual(update.status, "DRAFT")
    }
}
