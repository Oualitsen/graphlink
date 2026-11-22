import { ErrItemService } from '../generated/services/err-item-service.js';
import { ErrNotFound } from '../generated/errors/err-not-found.js';
import { ErrForbidden } from '../generated/errors/err-forbidden.js';
import { ErrConflict } from '../generated/errors/err-conflict.js';
import { ErrItem } from '../generated/types/err-item.js';

export class ErrItemServiceImpl implements ErrItemService {
  async errProbe(id: string): Promise<ErrItem> {
    if (id === 'missing') throw new ErrNotFound({ id, message: `Item ${id} not found` });
    if (id === 'forbidden') throw new ErrForbidden({ message: 'No access' });
    if (id === 'boom') throw new Error('secret detail');
    return { id };
  }

  async errRest(id: string): Promise<ErrItem> {
    if (id === 'missing') throw new ErrNotFound({ id, message: `Item ${id} not found` });
    if (id === 'conflict') throw new ErrConflict({ reason: 'duplicate', message: 'Conflict' });
    if (id === 'boom') throw new Error('secret detail');
    return { id };
  }
}
