package tests

import (
	"testing"

	gl "graphlink.dev/mocktests/generated"
)

func intPtr(v int) *int { return &v }

func TestTypeWithSeveralTargets(t *testing.T) {
	article := gl.MappedArticle{Id: "a1", Title: "Hello", Body: "Body text", Views: intPtr(7)}
	unviewed := gl.MappedArticle{Id: "a2", Title: "Quiet", Body: "No readers"}

	t.Run("summary renames title to headline", func(t *testing.T) {
		summary := article.ToMappedArticleSummary()
		expectEqual(t, summary.Id, "a1", "summary id")
		expectEqual(t, summary.Headline, "Hello", "summary headline")
	})

	t.Run("card renames title to name and keeps views", func(t *testing.T) {
		card := article.ToMappedArticleCard(99)
		expectEqual(t, card.Id, "a1", "card id")
		expectEqual(t, card.Name, "Hello", "card name")
		expectEqual(t, card.Views, 7, "card views")
	})

	t.Run("card uses defaultViews when views is nil", func(t *testing.T) {
		card := unviewed.ToMappedArticleCard(99)
		expectEqual(t, card.Name, "Quiet", "card name")
		expectEqual(t, card.Views, 99, "card views")
	})

	t.Run("update input keeps title and takes status", func(t *testing.T) {
		update := article.ToMappedArticleUpdateInput("PUBLISHED")
		expectEqual(t, update.Id, "a1", "update id")
		expectEqual(t, update.Title, "Hello", "update title")
		expectEqual(t, update.Body, "Body text", "update body")
		expectEqual(t, update.Status, "PUBLISHED", "update status")
	})
}

func TestInputWithSeveralTargets(t *testing.T) {
	draft := gl.MappedArticleDraftInput{Title: "Draft", Body: "Text", Views: intPtr(3)}
	bare := gl.MappedArticleDraftInput{Title: "Bare", Body: "Nothing"}

	t.Run("ToMappedArticle copies the fields and takes id", func(t *testing.T) {
		mapped := draft.ToMappedArticle("d1")
		expectEqual(t, mapped.Id, "d1", "id")
		expectEqual(t, mapped.Title, "Draft", "title")
		expectEqual(t, mapped.Body, "Text", "body")
		if mapped.Views == nil || *mapped.Views != 3 {
			t.Fatalf("views: got %v, want 3", mapped.Views)
		}
	})

	t.Run("ToMappedArticle keeps a nil views", func(t *testing.T) {
		if bare.ToMappedArticle("d2").Views != nil {
			t.Fatal("views should stay nil")
		}
	})

	t.Run("ToMappedArticleUpdateInput takes id and status", func(t *testing.T) {
		update := draft.ToMappedArticleUpdateInput("d1", "DRAFT")
		expectEqual(t, update.Id, "d1", "id")
		expectEqual(t, update.Title, "Draft", "title")
		expectEqual(t, update.Body, "Text", "body")
		expectEqual(t, update.Status, "DRAFT", "status")
	})
}
