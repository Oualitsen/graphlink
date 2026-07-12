import { describe, test, expect } from 'vitest';
import { newClient } from './fixtures.js';
import type { GreetingReceivedResponse } from '../src/generated/types/greeting-received-response.js';
import type { ListTeamsFieldArgs } from '../src/generated/inputs/list-teams-field-args.js';

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

describe('@glIntercept', () => {
  const client = newClient();

  test('greetIntercepted appends the runBefore marker to the name argument', async () => {
    const res = await client.queries.greetIntercepted({ name: 'Ada' });
    expect(res.greetIntercepted.message).toBe('Hello, Ada(runBefore)');
  });

  test('greetPlain is not intercepted, no marker appended', async () => {
    const res = await client.queries.greetPlain({ name: 'Ada' });
    expect(res.greetPlain.message).toBe('Hello, Ada');
  });

  test('greetingReceived (intercepted subscription) bakes the marker into every emitted greeting', async () => {
    const eventPromise = new Promise<GreetingReceivedResponse>((resolve, reject) => {
      const timer = setTimeout(() => {
        unsubscribe();
        reject(new Error('Timeout waiting for greetingReceived event'));
      }, 10000);

      const unsubscribe = client.subscriptions.greetingReceived(
        (data) => {
          clearTimeout(timer);
          unsubscribe();
          resolve(data);
        },
        (err) => {
          clearTimeout(timer);
          unsubscribe();
          reject(err);
        },
      );
    });

    // give the subscription a moment to register (and runBefore to fire) before triggering the mutation
    await sleep(300);

    await client.mutations.sendGreeting({ name: 'Ada' });

    const event = await eventPromise;
    expect(event.greetingReceived.message).toBe('Hello, Ada(runBefore)');
  });

  test('Team.members (intercepted mapping) allows role "auth"', async () => {
    const fieldArgs: ListTeamsFieldArgs = { membersRole: 'auth' };
    const res = await client.queries.listTeams({ fieldArgs });
    const members = new Set(res.listTeams[0].members.map((m) => m.name));
    expect(members).toEqual(new Set(['Ada', 'Grace']));
  });

  test('Team.members (intercepted mapping) denies any other role', async () => {
    const fieldArgs: ListTeamsFieldArgs = { membersRole: 'wrong' };
    await expect(client.queries.listTeams({ fieldArgs })).rejects.toBeTruthy();
  });
});
