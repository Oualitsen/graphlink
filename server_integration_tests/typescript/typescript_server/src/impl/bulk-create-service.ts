import { BulkCreateService } from '../generated/services/bulk-create-service.js';
import { BulkCreateGuard } from '../generated/guards/bulk-create-guard.js';
import { CreateArticleInput } from '../generated/inputs/create-article-input.js';

export class BulkCreateServiceImpl implements BulkCreateService {
  async bulkCreate(_matrix: (CreateArticleInput[] | null)[] | null): Promise<number> {
    return 0;
  }
}

export class BulkCreateGuardImpl implements BulkCreateGuard {
  async validateBulkCreate(_matrix: (CreateArticleInput[] | null)[] | null): Promise<void> {}
}
