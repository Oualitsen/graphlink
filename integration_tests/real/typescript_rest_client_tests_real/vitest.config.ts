import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

const axios = process.env.REST_VARIANT === 'axios';
const path = (relative: string): string => fileURLToPath(new URL(relative, import.meta.url));

export default defineConfig({
  resolve: {
    alias: axios
      ? [
          { find: /^\.\.\/lib\/generated\/graphlink$/, replacement: path('./axios/lib/generated/graphlink') },
          { find: /^\.\/rest-adapter$/, replacement: path('./test/rest-adapter-axios') },
        ]
      : [],
  },
  test: {
    fileParallelism: false,
    testTimeout: 30000,
    hookTimeout: 30000,
  },
});
