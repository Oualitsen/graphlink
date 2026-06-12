import { AuthorSchemaMappingsService } from '../generated/services/author-schema-mappings-service.js';
import { Author } from '../generated/types/author.js';
import { Article } from '../generated/types/article.js';
import { articles } from './data.js';

export class AuthorSchemaMappingsServiceImpl implements AuthorSchemaMappingsService {
  async authorArticles(items: Author[]): Promise<Map<Author, Article[]>> {
    const map = new Map<Author, Article[]>();
    for (const author of items) {
      map.set(author, articles.filter((a) => a.authorId === author.id));
    }
    return map;
  }

  async authorLatestArticles(item: Author, limit: number): Promise<Article[]> {
    return articles
      .filter((a) => a.authorId === item.id)
      .slice(-limit)
      .reverse();
  }
}
