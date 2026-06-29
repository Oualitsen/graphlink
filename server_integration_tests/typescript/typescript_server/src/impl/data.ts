import { readFileSync } from 'fs';
import { Author } from '../generated/types/author.js';
import { Article } from '../generated/types/article.js';

const fixtures = JSON.parse(readFileSync(process.env.FIXTURES_PATH ?? '../../fixtures.json', 'utf-8'));

export const authors: Author[] = fixtures.authors;
export const articles: Article[] = fixtures.articles;
let nextArticleId: number = fixtures.nextId;

export function nextId(): string {
  return String(nextArticleId++);
}
