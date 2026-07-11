import { AuthorSchemaMappingsService } from '../generated/services/author-schema-mappings-service.js';
import { Author } from '../generated/types/author.js';
import { Article } from '../generated/types/article.js';
import { articles } from './data.js';

export class AuthorSchemaMappingsServiceImpl implements AuthorSchemaMappingsService {
  async authorArticles(value: Author[]): Promise<Map<Author, Article[] | null>> {
    const result = new Map<Author, Article[] | null>();
    for (const author of value) {
      result.set(author, articles.filter((a) => a.authorId === author.id));
    }
    return result;
  }

  async authorLatestArticles(limit: number, value: Author): Promise<Article[]> {
    return articles.filter((a) => a.authorId === value.id).slice(0, limit);
  }
}
