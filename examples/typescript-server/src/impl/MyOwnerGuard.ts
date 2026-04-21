import { OwnerGuard } from '../generated/guards/owner-guard.js';
import { AddOwnerInput } from '../generated/inputs/add-owner-input.js';

export class MyOwnerGuard implements OwnerGuard {
  async validateAddOwner(input: AddOwnerInput): Promise<void> {
    if (!input.name?.trim()) throw new Error('Owner name cannot be empty');
    if (!input.email?.includes('@')) throw new Error('Invalid email address');
  }
}
