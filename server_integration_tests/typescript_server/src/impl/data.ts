import { Author } from '../generated/types/author.js';
import { Article } from '../generated/types/article.js';

export const authors: Author[] = [
  { id: '1', name: 'Ramdane' },
  { id: '2', name: 'Alice' },
];

export const articles: Article[] = [
  { id: '1', title: 'GraphLink Basics', authorId: '1' },
  { id: '2', title: 'Advanced GraphLink', authorId: '1' },
  { id: '3', title: "Alice's First Post", authorId: '2' },
];

let nextArticleId = 4;

export function nextId(): string {
  return String(nextArticleId++);
}
