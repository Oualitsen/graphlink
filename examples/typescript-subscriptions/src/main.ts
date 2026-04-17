import { readFileSync } from 'fs';
import { GraphLinkClient, DefaultGraphLinkWsAdapter } from './generated/client/graph-link-client.ts';
import { createFetchAdapter } from './generated/client/graph-link-adapters.ts';
import { CreatePersonInput } from './generated/inputs/create-person-input.ts';
import { CreateCarInput } from './generated/inputs/create-car-input.ts';

const SERVER_URL = 'http://localhost:8080/graphql';
const WS_URL = 'ws://localhost:8080/graphql';

// ── Client ────────────────────────────────────────────────────────────────────
const client = new GraphLinkClient(
  createFetchAdapter(SERVER_URL),
  new DefaultGraphLinkWsAdapter(WS_URL),
);

// ── Queries ───────────────────────────────────────────────────────────────────
async function runQueries() {
  const personRes = await client.queries.person({ id: '1' });
  console.log('person:', personRes.person);

  const carRes = await client.queries.car({ id: '1' });
  console.log('car:', carRes.car);
}

// ── Mutations ─────────────────────────────────────────────────────────────────
async function runMutations() {
  const personInput: CreatePersonInput = { name: 'Alice', age: 30 };
  const createPersonRes = await client.mutations.createPerson({ input: personInput });
  console.log('createPerson:', createPersonRes.createPerson);

  const carInput: CreateCarInput = { brand: 'Toyota', model: 'Camry', ownerId: '1' };
  const createCarRes = await client.mutations.createCar({ input: carInput });
  console.log('createCar:', createCarRes.createCar);
}

// ── Upload ────────────────────────────────────────────────────────────────────
function fileAsGLUpload(filePath: string, filename: string) {
  const buffer = readFileSync(filePath);
  const blob = new Blob([buffer], { type: 'text/typescript' });
  return { stream: blob, length: blob.size, filename, mimeType: 'text/typescript' };
}



// ── Subscriptions ─────────────────────────────────────────────────────────────
function runSubscription(label: string): () => void {
  console.log(`[${label}] listening for personCreated events...`);
  return client.subscriptions.personCreated(
    (event) => {
      console.log(`[${label}] personCreated:`, event.personCreated);
    },
    (err) => {
      console.error(`[${label}] subscription error:`, err);
    },
  );
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  try {
  //  await runQueries();
  //  await runMutations();
    const cancel1 = runSubscription('sub-1');
   // const cancel2 = runSubscription('sub-2');
    // cancel both after 15 seconds
   //setTimeout(() => { cancel1();  }, 3_000);
  } catch (e) {
    console.error('Error:', e);
  }
}

main();
