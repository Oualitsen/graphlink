import { GreetingService } from '../generated/services/greeting-service.js';
import { GraphLinkContext } from '../generated/context.js';
import { Greeting } from '../generated/types/greeting.js';
import { SimplePubSub } from './pubsub.js';

const greetingReceivedPubSub = new SimplePubSub<Greeting>();

async function* withMarker(source: AsyncIterable<Greeting>, marker: string | undefined): AsyncIterable<Greeting> {
  for await (const greeting of source) {
    yield marker ? { ...greeting, message: `${greeting.message}${marker}` } : greeting;
  }
}

export class GreetingServiceImpl implements GreetingService {
  private buildGreeting(name: string, marker?: string): Greeting {
    return { id: '1', message: `Hello, ${name}${marker ?? ''}` };
  }

  async greetIntercepted(name: string, context: GraphLinkContext): Promise<Greeting> {
    return this.buildGreeting(name, context.marker);
  }

  async greetPlain(name: string): Promise<Greeting> {
    return this.buildGreeting(name);
  }

  async sendGreeting(name: string): Promise<Greeting> {
    const greeting = this.buildGreeting(name);
    greetingReceivedPubSub.publish(greeting);
    return greeting;
  }

  // `runBefore` (and the marker it sets on `context`) has already completed
  // by the time this method runs — the generated subscribe resolver awaits
  // it first — so the marker is captured once, here, and baked into every
  // subsequently emitted greeting for the lifetime of this subscription.
  greetingReceived(context: GraphLinkContext): AsyncIterable<Greeting> {
    return withMarker(greetingReceivedPubSub.asyncIterator(), context.marker);
  }
}
