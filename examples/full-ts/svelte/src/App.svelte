<script lang="ts">
  import { onMount } from 'svelte';
  import { GraphLinkClient, DefaultGraphLinkWsAdapter } from './generated/client/graph-link-client.js';
  import { createFetchAdapter } from './generated/client/graph-link-adapters.js';

  interface Todo {
    id: string;
    title: string;
    completed: boolean;
  }

  const adapter = createFetchAdapter('http://localhost:4000/graphql');
  const wsAdapter = new DefaultGraphLinkWsAdapter('ws://localhost:4000/graphql');
  const client = new GraphLinkClient(adapter, wsAdapter);

  let todos = $state<Todo[]>([]);
  let newTitle = $state('');

  onMount(async () => {
    const data = await client.queries.getTodos();
    todos = data.todos;

    // Real-time: new todos pushed by the server land here
    const unsub = client.subscriptions.onTodoAdded(
      (data) => { todos = [...todos, data.todoAdded]; },
    );

    return () => unsub();
  });

  async function addTodo() {
    const title = newTitle.trim();
    if (!title) return;
    // Subscription delivers the new todo — just clear the input here
    await client.mutations.createTodo({ input: { title } });
    newTitle = '';
  }

  async function toggleTodo(id: string) {
    const data = await client.mutations.toggleTodo({ id });
    todos = todos.map((t) => (t.id === id ? data.toggleTodo : t));
  }

  async function deleteTodo(id: string) {
    await client.mutations.deleteTodo({ id });
    todos = todos.filter((t) => t.id !== id);
  }
</script>

<div>
  <h1>GraphLink Todo — Svelte</h1>

  <div>
    <input bind:value={newTitle} placeholder="New todo…" onkeyup={(e) => e.key === 'Enter' && addTodo()} />
    <button onclick={addTodo}>Add</button>
  </div>

  <ul>
    {#if todos.length === 0}
      <li>No todos yet.</li>
    {/if}
    {#each todos as todo (todo.id)}
      <li>
        <input type="checkbox" checked={todo.completed} onchange={() => toggleTodo(todo.id)} />
        <span style:text-decoration={todo.completed ? 'line-through' : 'none'}>
          {todo.title}
        </span>
        <button onclick={() => deleteTodo(todo.id)}>✕</button>
      </li>
    {/each}
  </ul>
</div>
