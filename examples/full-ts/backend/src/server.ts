import express from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';

const app = express();
app.use(cors());
app.use(express.json());

// ── In-memory store ───────────────────────────────────────────────────────────

interface Todo {
  id: string;
  title: string;
  completed: boolean;
}

let todos: Todo[] = [];
let nextId = 1;

// ── Subscription registry ─────────────────────────────────────────────────────

interface Subscriber {
  ws: WebSocket;
  subId: string;
}

let wsCounter = 0;
const todoAddedSubs = new Map<string, Subscriber>();

function broadcastTodoAdded(todo: Todo): void {
  const msg = (subId: string) =>
    JSON.stringify({ type: 'next', id: subId, payload: { data: { todoAdded: todo } } });
  for (const [, sub] of todoAddedSubs) {
    if (sub.ws.readyState === WebSocket.OPEN) sub.ws.send(msg(sub.subId));
  }
}

// ── HTTP GraphQL handler ──────────────────────────────────────────────────────

app.post('/graphql', (req, res) => {
  const { operationName, variables } = req.body as {
    operationName: string;
    variables: Record<string, unknown>;
  };

  switch (operationName) {
    case 'getTodos':
      return res.json({ data: { todos } });

    case 'getTodo':
      return res.json({ data: { todo: todos.find((t) => t.id === variables['id']) ?? null } });

    case 'createTodo': {
      const input = variables['input'] as { title: string };
      const todo: Todo = { id: String(nextId++), title: input.title, completed: false };
      todos.push(todo);
      broadcastTodoAdded(todo);
      return res.json({ data: { createTodo: todo } });
    }

    case 'toggleTodo': {
      const todo = todos.find((t) => t.id === variables['id']);
      if (!todo) return res.json({ errors: [{ message: 'Todo not found' }] });
      todo.completed = !todo.completed;
      return res.json({ data: { toggleTodo: todo } });
    }

    case 'deleteTodo': {
      const idx = todos.findIndex((t) => t.id === variables['id']);
      if (idx === -1) return res.json({ errors: [{ message: 'Todo not found' }] });
      todos.splice(idx, 1);
      return res.json({ data: { deleteTodo: true } });
    }

    default:
      return res.status(400).json({ errors: [{ message: `Unknown operation: ${operationName}` }] });
  }
});

// ── WebSocket — graphql-transport-ws protocol ─────────────────────────────────

const server = createServer(app);
const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
  const wsId = String(++wsCounter);
  const activeSubs = new Set<string>();

  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString()) as {
      type: string;
      id?: string;
      payload?: { operationName?: string };
    };

    switch (msg.type) {
      case 'connection_init':
        ws.send(JSON.stringify({ type: 'connection_ack' }));
        break;

      case 'ping':
        ws.send(JSON.stringify({ type: 'pong' }));
        break;

      case 'subscribe': {
        const subId = msg.id!;
        const opName = msg.payload?.operationName;
        activeSubs.add(subId);
        if (opName === 'onTodoAdded') {
          todoAddedSubs.set(`${wsId}:${subId}`, { ws, subId });
        }
        break;
      }

      case 'complete': {
        const subId = msg.id!;
        todoAddedSubs.delete(`${wsId}:${subId}`);
        activeSubs.delete(subId);
        break;
      }
    }
  });

  ws.on('close', () => {
    for (const subId of activeSubs) todoAddedSubs.delete(`${wsId}:${subId}`);
  });
});

server.listen(4000, () => {
  console.log('GraphLink backend → http://localhost:4000/graphql');
  console.log('                    ws://localhost:4000/graphql');
});
