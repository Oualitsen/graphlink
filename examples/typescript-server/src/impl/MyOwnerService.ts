import { OwnerService } from '../generated/services/owner-service.js';
import { Owner } from '../generated/types/owner.js';
import { AddOwnerInput } from '../generated/inputs/add-owner-input.js';

const owners: Owner[] = [
  { id: '1', name: 'Alice', email: 'alice@example.com' },
  { id: '2', name: 'Bob', email: 'bob@example.com' },
];

export class MyOwnerService implements OwnerService {
  async getOwner(id: string): Promise<Owner | null> {
    return owners.find(o => o.id === id) ?? null;
  }

  async addOwner(input: AddOwnerInput): Promise<Owner> {
    const owner: Owner = {
      id: String(owners.length + 1),
      name: input.name,
      email: input.email,
    };
    owners.push(owner);
    return owner;
  }
}
