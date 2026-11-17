import { StatusService } from '../generated/services/status-service.js';

export class StatusServiceImpl implements StatusService {
  async _status(): Promise<string> {
    return 'ok';
  }
}
