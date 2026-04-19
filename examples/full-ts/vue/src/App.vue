<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
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

const todos = ref<Todo[]>([]);
const newTitle = ref('');
let unsub: (() => void) | null = null;

onMounted(async () => {
  const data = await client.queries.getTodos();
  todos.value = data.todos;

  // Real-time: new todos pushed by the server land here
  unsub = client.subscriptions.onTodoAdded(
    (data) => { todos.value = [...todos.value, data.todoAdded]; },
  );
});

onUnmounted(() => unsub?.());

async function addTodo() {
  const title = newTitle.value.trim();
  if (!title) return;
  // Subscription delivers the new todo — just clear the input here
  await client.mutations.createTodo({ input: { title } });
  newTitle.value = '';
}

async function toggleTodo(id: string) {
  const data = await client.mutations.toggleTodo({ id });
  todos.value = todos.value.map((t) => (t.id === id ? data.toggleTodo : t));
}

async function deleteTodo(id: string) {
  await client.mutations.deleteTodo({ id });
  todos.value = todos.value.filter((t) => t.id !== id);
}
</script>

<template>
  <div>
    <h1>GraphLink Todo — Vue</h1>

    <div>
      <input v-model="newTitle" placeholder="New todo…" @keyup.enter="addTodo" />
      <button @click="addTodo">Add</button>
    </div>

    <ul>
      <li v-if="todos.length === 0">No todos yet.</li>
      <li v-for="todo in todos" :key="todo.id">
        <input type="checkbox" :checked="todo.completed" @change="toggleTodo(todo.id)" />
        <span :style="{ textDecoration: todo.completed ? 'line-through' : 'none' }">
          {{ todo.title }}
        </span>
        <button @click="deleteTodo(todo.id)">✕</button>
      </li>
    </ul>
  </div>
</template>
