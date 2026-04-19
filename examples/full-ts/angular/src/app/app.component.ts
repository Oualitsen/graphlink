import { Component, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { GraphLinkClient, DefaultGraphLinkWsAdapter } from '../generated/client/graph-link-client.js';
import { createFetchAdapter } from '../generated/client/graph-link-adapters.js';

interface Todo {
  id: string;
  title: string;
  completed: boolean;
}

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <h1>GraphLink Todo — Angular</h1>

    <div>
      <input
        [(ngModel)]="newTitle"
        placeholder="New todo…"
        (keyup.enter)="addTodo()"
      />
      <button (click)="addTodo()">Add</button>
    </div>

    <ul>
      @for (todo of todos; track todo.id) {
        <li>
          <input
            type="checkbox"
            [checked]="todo.completed"
            (change)="toggleTodo(todo.id)"
          />
          <span [style.textDecoration]="todo.completed ? 'line-through' : 'none'">
            {{ todo.title }}
          </span>
          <button (click)="deleteTodo(todo.id)">✕</button>
        </li>
      } @empty {
        <li>No todos yet.</li>
      }
    </ul>
  `,
})
export class AppComponent implements OnInit, OnDestroy {
  todos: Todo[] = [];
  newTitle = '';

  private readonly client: GraphLinkClient;
  private todoSub?: Subscription;

  constructor() {
    const adapter = createFetchAdapter('http://localhost:4000/graphql');
    const wsAdapter = new DefaultGraphLinkWsAdapter('ws://localhost:4000/graphql');
    this.client = new GraphLinkClient(adapter, wsAdapter);
  }

  ngOnInit(): void {
    this.client.queries.getTodos().subscribe({
      next: (data) => (this.todos = data.todos),
    });

    // Real-time: new todos pushed by the server land here
    this.todoSub = this.client.subscriptions.onTodoAdded().subscribe({
      next: (data) => {
        this.todos = [...this.todos, data.todoAdded];
      },
    });
  }

  ngOnDestroy(): void {
    this.todoSub?.unsubscribe();
  }

  addTodo(): void {
    const title = this.newTitle.trim();
    if (!title) return;
    // Subscription delivers the new todo — just clear the input here
    this.client.mutations.createTodo({ input: { title } }).subscribe({
      next: () => (this.newTitle = ''),
    });
  }

  toggleTodo(id: string): void {
    this.client.mutations.toggleTodo({ id }).subscribe({
      next: (data) => {
        this.todos = this.todos.map((t) => (t.id === id ? data.toggleTodo : t));
      },
    });
  }

  deleteTodo(id: string): void {
    this.client.mutations.deleteTodo({ id }).subscribe({
      next: () => {
        this.todos = this.todos.filter((t) => t.id !== id);
      },
    });
  }
}
