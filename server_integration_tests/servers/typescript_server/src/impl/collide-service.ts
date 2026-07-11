import { CollideService } from '../generated/services/collide-service.js';
import { Collide } from '../generated/types/collide.js';

export class CollideServiceImpl implements CollideService {
  // The two colliding wire fields (`class` and `class_`) carry distinct values
  // so the round-trip can prove they stayed separate identifiers.
  async collide(): Promise<Collide> {
    return { id: '1', class: 'A', class2: 'B' };
  }
}
