import { ArticleService } from '../generated/services/article-service.js';
import { Article } from '../generated/types/article.js';
import { ArticleType } from '../generated/enums/article-type.js';
import { CreateArticleInput } from '../generated/inputs/create-article-input.js';
import { UpdateArticleInput } from '../generated/inputs/update-article-input.js';
import { articles, nextId } from './data.js';
import { SimplePubSub } from './pubsub.js';

const articleCreatedPubSub = new SimplePubSub<Article>();
const articleUpdatedPubSub = new SimplePubSub<Article>();

export class ArticleServiceImpl implements ArticleService {
  async getArticle(id: string): Promise<Article> {
    const article = articles.find((a) => a.id === id);
    if (!article) throw new Error(`Article not found: ${id}`);
    return article;
  }

  async listArticles(): Promise<Article[]> {
    return articles;
  }

  async createArticle(input: CreateArticleInput): Promise<Article> {
    const article: Article = {
      id: nextId(),
      title: input.title,
      type: null,
      authorId: input.authorId,
      webSite: null,
      published: false,
    };
    articles.push(article);
    articleCreatedPubSub.publish(article);
    return article;
  }

  async updateArticle(input: UpdateArticleInput): Promise<Article> {
    const index = articles.findIndex((a) => a.id === input.id);
    if (index < 0) throw new Error(`Article not found: ${input.id}`);
    const updated: Article =
      input.title != null ? { ...articles[index], title: input.title } : articles[index];
    articles[index] = updated;
    articleUpdatedPubSub.publish(updated);
    return updated;
  }

  articleCreated(): AsyncIterable<Article> {
    return articleCreatedPubSub.asyncIterator();
  }

  articleUpdated(id: string): AsyncIterable<Article> {
    return articleUpdatedPubSub.asyncIterator((article) => article.id === id);
  }

  async *articleDeleted(): AsyncIterable<string> {
    yield 'deleted-1';
    yield 'deleted-2';
  }

  // Article implements Article, so a concrete article is a valid projection —
  // the client selects whichever subset it wants.
  async getProjectedArticle(): Promise<Article> {
    return articles[0];
  }

  async getArticleInfo(): Promise<Article | null> {
    return articles[0] ?? null;
  }

  async getArticleWithCount(): Promise<Article | null> {
    return articles[0] ?? null;
  }

  async getArticleTypes(): Promise<ArticleType[]> {
    return [ArticleType.News, ArticleType.Blog, ArticleType.Review];
  }
}
