import { BulkCreateService } from '../generated/services/bulk-create-service.js';
import { BulkCreateGuard } from '../generated/guards/bulk-create-guard.js';
import { CreateArticleInput } from '../generated/inputs/create-article-input.js';

type Matrix = (CreateArticleInput[] | null)[] | null;

const inputs = (matrix: Matrix): CreateArticleInput[] => (matrix ?? []).flatMap((row) => row ?? []);

// Counts the inputs it received, so a test can see how the nested list was decoded.
export class BulkCreateServiceImpl implements BulkCreateService {
  async bulkCreate(matrix: Matrix): Promise<number> {
    return inputs(matrix).length;
  }
}

export class BulkCreateGuardImpl implements BulkCreateGuard {
  async validateBulkCreate(matrix: Matrix): Promise<void> {
    if (inputs(matrix).some((input) => input.title === 'invalid')) throw new Error('invalid title');
  }
}
