import { PingService } from '../generated/services/ping-service.js';

export class PingServiceImpl implements PingService {
  async ping(): Promise<boolean> {
    return true;
  }
}
