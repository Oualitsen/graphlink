import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { Car, Bike } from '../lib/generated/graphlink.js';
import { newClient } from './real-server-adapter.ts';

// Cycle: VehicleDriver → Vehicle (Car|Bike) → VehicleOwner → VehicleDriver
//
// VehicleDriver is annotated @glExpand(depth: 3) in the schema, so the
// auto-generated query recurses 3 hops into the cycle:
//
//   layer 1 — VehicleDriver.vehicle          (Car or Bike)
//   layer 2 — Car/Bike.owner                 (VehicleOwner)
//   layer 3 — VehicleOwner.driver            (VehicleDriver, no vehicle selected)

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('layer 1 — VehicleDriver.vehicle', () => {
  it('returns the driver id and name', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-1' });
    expect(res.getVehicleDriver.id).toBe('vd-1');
    expect(res.getVehicleDriver.name).toBe('Alex Driver');
  });

  it('vehicle is not null (selected at layer 1)', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-1' });
    expect(res.getVehicleDriver.vehicle).not.toBeNull();
  });

  it('Car variant: vehicle is a Car with correct model', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-1' });
    const vehicle = res.getVehicleDriver.vehicle;
    expect(vehicle).toBeInstanceOf(Car);
    expect((vehicle as Car).model).toBe('Tesla Model 3');
  });

  it('Bike variant: vehicle is a Bike with correct brand', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-2' });
    const vehicle = res.getVehicleDriver.vehicle;
    expect(vehicle).toBeInstanceOf(Bike);
    expect((vehicle as Bike).brand).toBe('Trek FX3');
  });
});

describe('layer 2 — Vehicle.owner', () => {
  it('Car.owner is not null (selected at layer 2)', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-1' });
    expect(res.getVehicleDriver.vehicle?.owner).not.toBeNull();
  });

  it('Car.owner has correct id and name', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-1' });
    const owner = res.getVehicleDriver.vehicle?.owner;
    expect(owner?.id).toBe('vo-1');
    expect(owner?.name).toBe('Alice Owner');
  });

  it('Bike.owner has correct id and name', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-2' });
    const owner = res.getVehicleDriver.vehicle?.owner;
    expect(owner?.id).toBe('vo-2');
    expect(owner?.name).toBe('Bob Owner');
  });
});

describe('layer 3 — VehicleOwner.driver', () => {
  it('owner.driver is not null (selected at layer 3)', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-1' });
    expect(res.getVehicleDriver.vehicle?.owner?.driver).not.toBeNull();
  });

  it('owner.driver has correct id and name', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-1' });
    const driver = res.getVehicleDriver.vehicle?.owner?.driver;
    expect(driver?.id).toBe('vd-1');
    expect(driver?.name).toBe('Alex Driver');
  });
});

describe('layer 4 — cycle truncated at depth 3', () => {
  it('owner.driver.vehicle is null for Car variant', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-1' });
    expect(res.getVehicleDriver.vehicle?.owner?.driver?.vehicle).toBeNull();
  });

  it('owner.driver.vehicle is null for Bike variant', async () => {
    const res = await client.queries.getVehicleDriver({ id: 'vd-2' });
    expect(res.getVehicleDriver.vehicle?.owner?.driver?.vehicle).toBeNull();
  });
});
