import { AuthorService } from '../generated/services/author-service.js';
import { Author } from '../generated/types/author.js';
import { authors } from './data.js';

export class AuthorServiceImpl implements AuthorService {
  async getAuthor(id: string): Promise<Author | null> {
    return authors.find((a) => a.id === id) ?? null;
  }

  async listAuthors(): Promise<Author[]> {
    return authors;
  }
}
