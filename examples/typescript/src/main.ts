import { readFileSync } from 'fs';
import { GraphLinkClient, DefaultGraphLinkWsAdapter } from './generated/client/graph-link-client.ts';
import { createFetchAdapter, createMultipartFetchAdapter } from './generated/client/graph-link-adapters.ts';
import { CreatePersonInput } from './generated/inputs/create-person-input.ts';
import { CreateCarInput } from './generated/inputs/create-car-input.ts';

const SERVER_URL = 'http://localhost:8080/graphql';
const WS_URL = 'ws://localhost:8080/graphql';

// ── Client ────────────────────────────────────────────────────────────────────
const client = new GraphLinkClient(
  createFetchAdapter(SERVER_URL),
  new DefaultGraphLinkWsAdapter(WS_URL),
  createMultipartFetchAdapter(SERVER_URL),
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

async function runUpload() {
  const self = new URL(import.meta.url).pathname;

  const singleResult = await client.mutations.uploadFile(
    { file: fileAsGLUpload(self, 'main.ts') },
    (sent, total) => console.log(`uploadFile progress: ${sent}/${total}`),
  );
  console.log('uploadFile bytes received:', singleResult.uploadFile);

  const listResult = await client.mutations.uploadFileList(
    { file: [fileAsGLUpload(self, 'main.ts'), fileAsGLUpload(self, 'main-copy.ts')] },
    (sent, total) => console.log(`uploadFileList progress: ${sent}/${total}`),
  );
  console.log('uploadFileList bytes received:', listResult.uploadFileList);
}

// ── Subscriptions ─────────────────────────────────────────────────────────────
async function runSubscription() {
  console.log('listening for personCreated events (press Ctrl+C to stop)...');
  for await (const event of client.subscriptions.personCreated()) {
    console.log('personCreated:', event.personCreated);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  try {
    await runQueries();
    await runMutations();
    await runUpload();
    await runSubscription();
  } catch (e) {
    console.error('Error:', e);
  }
}

main();
