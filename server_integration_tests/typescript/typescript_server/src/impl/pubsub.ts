export class SimplePubSub<T> {
  private listeners = new Set<(payload: T) => void>();

  publish(payload: T): void {
    for (const listener of this.listeners) listener(payload);
  }

  asyncIterator(filter?: (payload: T) => boolean): AsyncIterable<T> {
    const listeners = this.listeners;
    const queue: T[] = [];
    let resolveNext: (() => void) | null = null;

    const listener = (payload: T) => {
      if (filter && !filter(payload)) return;
      queue.push(payload);
      if (resolveNext) {
        resolveNext();
        resolveNext = null;
      }
    };
    listeners.add(listener);

    return {
      [Symbol.asyncIterator]() {
        return {
          async next() {
            while (queue.length === 0) {
              await new Promise<void>((r) => {
                resolveNext = r;
              });
            }
            return { value: queue.shift()!, done: false };
          },
          async return() {
            listeners.delete(listener);
            return { value: undefined as any, done: true as const };
          },
        };
      },
    };
  }
}
