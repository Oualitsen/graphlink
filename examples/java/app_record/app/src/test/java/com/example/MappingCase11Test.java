package com.example;

import com.example.generated.inputs.UpdateArticleInput;
import com.example.generated.types.Article;
import com.example.generated.types.ArticleSummary;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 11 — @glMapsTo declared on a type, with several targets.
 * schema: Article @glMapsTo(type: "ArticleSummary") @glMapsTo(type: "UpdateArticleInput")
 *   title is renamed to headline for ArticleSummary only.
 */
class MappingCase11Test {

    private Article article() {
        return new Article("a1", "Hello", "Body text");
    }

    @Test
    void toArticleSummary_renamesTitleToHeadline() {
        ArticleSummary result = article().toArticleSummary();

        assertThat(result.id()).isEqualTo("a1");
        assertThat(result.headline()).isEqualTo("Hello");
    }

    @Test
    void toUpdateArticleInput_keepsTitleAndTakesStatusAsParam() {
        UpdateArticleInput result = article().toUpdateArticleInput("DRAFT");

        assertThat(result.title()).isEqualTo("Hello");
        assertThat(result.body()).isEqualTo("Body text");
        assertThat(result.status()).isEqualTo("DRAFT");
    }
}
