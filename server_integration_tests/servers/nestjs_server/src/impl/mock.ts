import { Product } from '../generated/types/product.js';

/** Deterministic synthesized data for the hoist-args resolvers. */
export const Mock = {
  products(prefix: string, count: number, offset: number): Product[] {
    return Array.from({ length: count }, (_, i) => {
      const n = offset + i;
      return { id: `${prefix}-${n}`, name: `${prefix}-${n}` };
    });
  },
};
