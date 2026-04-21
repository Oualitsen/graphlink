import { VehicleService } from '../generated/services/vehicle-service.js';
import { Vehicle } from '../generated/types/vehicle.js';
import { AddVehicleInput } from '../generated/inputs/add-vehicle-input.js';
import { VehicleStatus } from '../generated/enums/vehicle-status.js';
import { GraphLinkContext } from '../generated/context.js';
import { GraphQLResolveInfo } from 'graphql';

const vehicles: Vehicle[] = [
  { id: '1', brand: 'Toyota', year: 2022, status: VehicleStatus.ACTIVE },
  { id: '2', brand: 'Honda', year: 2021, status: VehicleStatus.SOLD },
];

export class MyVehicleService implements VehicleService {
  async getVehicle(id: string, context: GraphLinkContext, info: GraphQLResolveInfo): Promise<Vehicle | null> {
    return vehicles.find(v => v.id === id) ?? null;
  }

  async listVehicles(context: GraphLinkContext, info: GraphQLResolveInfo): Promise<Vehicle[]> {
    return vehicles;
  }

  async addVehicle(input: AddVehicleInput, context: GraphLinkContext, info: GraphQLResolveInfo): Promise<Vehicle> {
    const vehicle: Vehicle = {
      id: String(vehicles.length + 1),
      brand: input.brand,
      year: input.year,
      status: VehicleStatus.ACTIVE,
    };
    vehicles.push(vehicle);
    return vehicle;
  }

  async *vehicleStatusChanged(vehicleId: string, context: GraphLinkContext): AsyncIterable<Vehicle> {
    const statuses = [VehicleStatus.ACTIVE, VehicleStatus.INACTIVE, VehicleStatus.SOLD];
    for (let i = 0; i < 10; i++) {
      await new Promise(resolve => setTimeout(resolve, 500));
      const vehicle = vehicles.find(v => v.id === vehicleId);
      if (!vehicle) return;
      yield { ...vehicle, status: statuses[i % statuses.length] };
    }
  }
}
