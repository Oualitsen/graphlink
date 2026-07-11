import { DeleteArticleService } from '../generated/services/delete-article-service.js';
import { articles } from './data.js';

export class DeleteArticleServiceImpl implements DeleteArticleService {
  async deleteArticle(id: string): Promise<boolean> {
    const before = articles.length;
    for (let i = articles.length - 1; i >= 0; i--) {
      if (articles[i].id === id) articles.splice(i, 1);
    }
    return articles.length < before;
  }
}
