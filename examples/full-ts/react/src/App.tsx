import { useState, useEffect, useMemo } from 'react';
import { GraphLinkClient, DefaultGraphLinkWsAdapter } from './generated/client/graph-link-client.js';
import { createFetchAdapter } from './generated/client/graph-link-adapters.js';

interface Todo {
  id: string;
  title: string;
  completed: boolean;
}

export default function App() {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [newTitle, setNewTitle] = useState('');

  const client = useMemo(() => {
    const adapter = createFetchAdapter('http://localhost:4000/graphql');
    const wsAdapter = new DefaultGraphLinkWsAdapter('ws://localhost:4000/graphql');
    return new GraphLinkClient(adapter, wsAdapter);
  }, []);

  useEffect(() => {
    client.queries.getTodos().then((data) => setTodos(data.todos));

    // Real-time: new todos pushed by the server land here
    const unsub = client.subscriptions.onTodoAdded(
      (data) => setTodos((prev) => [...prev, data.todoAdded]),
    );
    return unsub;
  }, [client]);

  const addTodo = async () => {
    const title = newTitle.trim();
    if (!title) return;
    // Subscription delivers the new todo — just clear the input here
    await client.mutations.createTodo({ input: { title } });
    setNewTitle('');
  };

  const toggleTodo = async (id: string) => {
    const data = await client.mutations.toggleTodo({ id });
    setTodos((prev) => prev.map((t) => (t.id === id ? data.toggleTodo : t)));
  };

  const deleteTodo = async (id: string) => {
    await client.mutations.deleteTodo({ id });
    setTodos((prev) => prev.filter((t) => t.id !== id));
  };

  return (
    <div>
      <h1>GraphLink Todo — React</h1>

      <div>
        <input
          value={newTitle}
          onChange={(e) => setNewTitle(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && addTodo()}
          placeholder="New todo…"
        />
        <button onClick={addTodo}>Add</button>
      </div>

      <ul>
        {todos.length === 0 && <li>No todos yet.</li>}
        {todos.map((todo) => (
          <li key={todo.id}>
            <input
              type="checkbox"
              checked={todo.completed}
              onChange={() => toggleTodo(todo.id)}
            />
            <span style={{ textDecoration: todo.completed ? 'line-through' : 'none' }}>
              {todo.title}
            </span>
            <button onClick={() => deleteTodo(todo.id)}>✕</button>
          </li>
        ))}
      </ul>
    </div>
  );
}
