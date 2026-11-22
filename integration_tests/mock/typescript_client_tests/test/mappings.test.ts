import { describe, it, expect } from 'vitest';
import { MappedArticle } from '../lib/generated/types/mapped-article.js';
import { MappedArticleDraftInput } from '../lib/generated/inputs/mapped-article-draft-input.js';

const article: MappedArticle = { id: 'a1', title: 'Hello', body: 'Body text', views: 7 };
const unviewed: MappedArticle = { id: 'a2', title: 'Quiet', body: 'No readers', views: null };

describe('type with several targets', () => {
  it('toMappedArticleSummary renames title to headline', () => {
    const summary = MappedArticle.toMappedArticleSummary(article);
    expect(summary).toEqual({ id: 'a1', headline: 'Hello' });
  });

  it('toMappedArticleCard renames title to name and keeps views', () => {
    const card = MappedArticle.toMappedArticleCard(article, 99);
    expect(card).toEqual({ id: 'a1', name: 'Hello', views: 7 });
  });

  it('toMappedArticleCard uses defaultViews when views is null', () => {
    const card = MappedArticle.toMappedArticleCard(unviewed, 99);
    expect(card.name).toBe('Quiet');
    expect(card.views).toBe(99);
  });

  it('toMappedArticleUpdateInput keeps title and takes status as a parameter', () => {
    const update = MappedArticle.toMappedArticleUpdateInput(article, 'PUBLISHED');
    expect(update).toEqual({ id: 'a1', title: 'Hello', body: 'Body text', status: 'PUBLISHED' });
  });

  it('every mapping returns a new object', () => {
    expect(MappedArticle.toMappedArticleSummary(article)).not.toBe(article);
  });
});

describe('input with several targets', () => {
  const draft: MappedArticleDraftInput = { title: 'Draft', body: 'Text', views: 3 };
  const bare: MappedArticleDraftInput = { title: 'Bare', body: 'Nothing' };

  it('toMappedArticle copies the fields and takes id as a parameter', () => {
    const mapped = MappedArticleDraftInput.toMappedArticle(draft, 'd1');
    expect(mapped).toEqual({ id: 'd1', title: 'Draft', body: 'Text', views: 3 });
  });

  it('toMappedArticle turns a missing views into null', () => {
    expect(MappedArticleDraftInput.toMappedArticle(bare, 'd2').views).toBeNull();
  });

  it('toMappedArticleUpdateInput takes id and status as parameters', () => {
    const update = MappedArticleDraftInput.toMappedArticleUpdateInput(draft, 'd1', 'DRAFT');
    expect(update).toEqual({ id: 'd1', title: 'Draft', body: 'Text', status: 'DRAFT' });
  });
});
