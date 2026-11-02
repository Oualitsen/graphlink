import axios from 'axios';
import { createRestAxiosAdapter, type GLRestAdapter } from '../axios/lib/generated/graphlink';

export function createAdapter(baseUrl: string, headers?: () => Promise<Record<string, string>>): GLRestAdapter {
  return createRestAxiosAdapter(baseUrl, axios.create(), { headers });
}
