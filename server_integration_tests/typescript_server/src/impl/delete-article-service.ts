import { DeleteArticleService } from '../generated/services/delete-article-service.js';
import { articles } from './data.js';

export class DeleteArticleServiceImpl implements DeleteArticleService {
  async deleteArticle(id: string): Promise<boolean> {
    const index = articles.findIndex((a) => a.id === id);
    if (index === -1) return false;
    articles.splice(index, 1);
    return true;
  }
}
