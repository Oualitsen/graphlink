import { ArticleSchemaMappingsService } from '../generated/services/article-schema-mappings-service.js';
import { ArticleWithCountSchemaMappingsService } from '../generated/services/article-with-count-schema-mappings-service.js';
import { Article } from '../generated/types/article.js';
import { Author } from '../generated/types/author.js';
import { authors, articles } from './data.js';

export class ArticleSchemaMappingsServiceImpl
  implements ArticleSchemaMappingsService, ArticleWithCountSchemaMappingsService
{
  async articleAuthor(value: Article): Promise<Author> {
    const author = authors.find((a) => a.id === value.authorId);
    if (!author) throw new Error(`Author not found: ${value.authorId}`);
    return author;
  }

  async articleAuthorList(value: Article): Promise<Author[] | null> {
    return authors.filter((a) => a.id === value.authorId);
  }

  async articleWithCountCount(value: Article): Promise<number> {
    return articles.indexOf(value) + 1;
  }
}
