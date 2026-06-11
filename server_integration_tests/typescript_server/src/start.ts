import './impl/my-context.js';
import { createServer } from './generated/index.js';
import { AuthorServiceImpl } from './impl/author-service.js';
import { ArticleServiceImpl } from './impl/article-service.js';
import { DeleteArticleServiceImpl } from './impl/delete-article-service.js';
import { AuthorSchemaMappingsServiceImpl } from './impl/author-schema-mappings-service.js';
import { ArticleSchemaMappingsServiceImpl } from './impl/article-schema-mappings-service.js';

const PORT = 9997;

const httpServer = await createServer({
  authorService: new AuthorServiceImpl(),
  articleService: new ArticleServiceImpl(),
  deleteArticleService: new DeleteArticleServiceImpl(),
  authorSchemaMappingsService: new AuthorSchemaMappingsServiceImpl(),
  articleSchemaMappingsService: new ArticleSchemaMappingsServiceImpl(),
});

httpServer.listen(PORT, () => {
  console.log(`Server ready at http://localhost:${PORT}/graphql`);
});
