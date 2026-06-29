import { BulkCreateService } from '../generated/services/bulk-create-service.js';
import { BulkCreateGuard } from '../generated/guards/bulk-create-guard.js';
import { CreateArticleInput } from '../generated/inputs/create-article-input.js';
import { articles, nextId } from './data.js';

export class BulkCreateServiceImpl implements BulkCreateService {
  async bulkCreate(matrix: ((CreateArticleInput | null)[][] | null)[] | null): Promise<number> {
    if (matrix == null) return 0;
    let count = 0;
    for (const group of matrix) {
      if (group == null) continue;
      for (const batch of group) {
        if (batch == null) continue;
        for (const input of batch) {
          if (input != null) {
            articles.push({ id: nextId(), title: input.title, authorId: input.authorId });
            count++;
          }
        }
      }
    }
    return count;
  }
}

export class BulkCreateGuardImpl implements BulkCreateGuard {
  async validateBulkCreate(): Promise<void> {}
}
