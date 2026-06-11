import { ArticleSchemaMappingsService } from '../generated/services/article-schema-mappings-service.js';
import { Article } from '../generated/types/article.js';
import { Author } from '../generated/types/author.js';
import { authors } from './data.js';

export class ArticleSchemaMappingsServiceImpl implements ArticleSchemaMappingsService {
  async articleAuthor(item: Article): Promise<Author> {
    const author = authors.find((a) => a.id === item.authorId);
    if (!author) throw new Error(`Author not found: ${item.authorId}`);
    return author;
  }
}
