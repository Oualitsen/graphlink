import { ArticleService } from '../generated/services/article-service.js';
import { Article } from '../generated/types/article.js';
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
      authorId: input.authorId,
    };
    articles.push(article);
    articleCreatedPubSub.publish(article);
    return article;
  }

  async updateArticle(input: UpdateArticleInput): Promise<Article> {
    const article = articles.find((a) => a.id === input.id);
    if (!article) throw new Error(`Article not found: ${input.id}`);
    if (input.title !== undefined && input.title !== null) {
      Object.assign(article, { title: input.title });
    }
    articleUpdatedPubSub.publish(article);
    return article;
  }

  articleCreated(): AsyncIterable<Article> {
    return articleCreatedPubSub.asyncIterator();
  }

  articleUpdated(id: string): AsyncIterable<Article> {
    return articleUpdatedPubSub.asyncIterator((article) => article.id === id);
  }
}
