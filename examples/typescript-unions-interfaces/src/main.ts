import { readFileSync } from 'fs';
import { GraphLinkClient,  } from './generated/client/graph-link-client.ts';
import { createFetchAdapter } from './generated/client/graph-link-adapters.ts';

const SERVER_URL = 'http://localhost:8080/graphql';
const WS_URL = 'ws://localhost:8080/graphql';

const client = new GraphLinkClient(createFetchAdapter(SERVER_URL));

async function main() {
  client.queries.getAnimal({ id: '1' }).subscribe({
    next: (response) => {
      console.log('Animal:', response);
    }
  });
}
