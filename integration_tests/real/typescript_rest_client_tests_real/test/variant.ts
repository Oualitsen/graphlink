export interface Variant {
  comma: boolean;
  bracket: boolean;
  adapter: string;
  port: number;
  faultPort: number;
  key(base: string, path?: Array<string | number>): string;
  list(key: string, values: string[]): string[];
}

function make(comma: boolean, bracket: boolean, adapter: string, port: number, faultPort: number): Variant {
  return {
    comma,
    bracket,
    adapter,
    port,
    faultPort,
    key: (base, path = []) => path.reduce<string>((acc, p) => (bracket ? `${acc}[${p}]` : `${acc}.${p}`), base),
    list: (key, values) => (comma ? [`${key}=${values.join(',')}`] : values.map((v) => `${key}=${v}`)),
  };
}

export const variant: Variant =
  process.env.REST_VARIANT === 'axios' ? make(true, true, 'axios', 9989, 9969) : make(false, false, 'fetch', 9993, 9968);
