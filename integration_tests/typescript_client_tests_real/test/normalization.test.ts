import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { EventType } from '../lib/generated/enums/event-type.js';
import type { NormalizedInput } from '../lib/generated/inputs/normalized-input.js';
import { newClient } from './real-server-adapter.ts';

/**
 * End-to-end coverage for identifier normalization.
 *
 * Schema uses non-canonical field casing:
 *   - FirstName  → TypeScript codeName: firstName
 *   - last_name  → TypeScript codeName: lastName
 *   - USER_AGE   → TypeScript codeName: userAge
 *   - event_type → TypeScript codeName: eventType
 *
 * Enum values use PascalCase in TypeScript (wire: pending → Pending,
 * in_progress → InProgress, completed_ok → CompletedOk).
 */

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('EventType enum round-trip', () => {
  it('pending wire name → TypeScript codeName Pending', () => {
    expect(EventType.Pending).toBe('pending');
  });

  it('in_progress wire name → TypeScript codeName InProgress', () => {
    expect(EventType.InProgress).toBe('in_progress');
  });

  it('completed_ok wire name → TypeScript codeName CompletedOk', () => {
    expect(EventType.CompletedOk).toBe('completed_ok');
  });
});

describe('getNormalizedRecord — field normalization', () => {
  it('firstName is accessible (wire: FirstName)', async () => {
    const res = await client.queries.getNormalizedRecord({ id: 'rec-1' });
    expect(res.getNormalizedRecord.firstName).toBe('Alice');
  });

  it('lastName is accessible (wire: last_name)', async () => {
    const res = await client.queries.getNormalizedRecord({ id: 'rec-1' });
    expect(res.getNormalizedRecord.lastName).toBe('Smith');
  });

  it('userAge is accessible (wire: USER_AGE)', async () => {
    const res = await client.queries.getNormalizedRecord({ id: 'rec-1' });
    expect(res.getNormalizedRecord.userAge).toBe(30);
  });

  it('eventType is PascalCase enum (wire: in_progress → InProgress)', async () => {
    const res = await client.queries.getNormalizedRecord({ id: 'rec-1' });
    expect(res.getNormalizedRecord.eventType).toBe(EventType.InProgress);
  });
});

describe('createNormalizedRecord — input normalization', () => {
  it('normalized input fields round-trip through the server', async () => {
    const input: NormalizedInput = {
      firstName: 'Bob',
      lastName: 'Jones',
      eventType: EventType.CompletedOk,
    };
    const res = await client.mutations.createNormalizedRecord({ input });
    expect(res.createNormalizedRecord.firstName).toBe('Bob');
    expect(res.createNormalizedRecord.lastName).toBe('Jones');
    expect(res.createNormalizedRecord.eventType).toBe(EventType.CompletedOk);
  });
});
