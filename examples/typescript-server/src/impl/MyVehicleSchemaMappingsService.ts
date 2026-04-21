import { VehicleSchemaMappingsService } from '../generated/services/vehicle-schema-mappings-service.js';
import { Vehicle } from '../generated/types/vehicle.js';
import { Owner } from '../generated/types/owner.js';

const ownersByVehicleId: Record<string, Owner> = {
  '1': { id: '1', name: 'Alice', email: 'alice@example.com' },
  '2': { id: '2', name: 'Bob', email: 'bob@example.com' },
};

export class MyVehicleSchemaMappingsService implements VehicleSchemaMappingsService {
  async vehicleOwner(items: Vehicle[]): Promise<Map<Vehicle, Owner>> {
    const map = new Map<Vehicle, Owner>();
    for (const vehicle of items) {
      const owner = vehicle.id ? ownersByVehicleId[vehicle.id] : undefined;
      if (owner) map.set(vehicle, owner);
    }
    return map;
  }
}
