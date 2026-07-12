import { GraphLinkInterceptor } from '../generated/interfaces/graph-link-interceptor.js';
import { GlInterceptorTag } from '../generated/enums/gl-interceptor-tag.js';
import { GraphLinkContext } from '../generated/context.js';

export class InterceptorImpl implements GraphLinkInterceptor {
  runBefore(
    tag: GlInterceptorTag | null,
    operation: string,
    args: unknown[],
    context: GraphLinkContext | null,
  ): void {
    // `Team.members(role: String!)` demonstrates the throw-to-deny contract
    // directly: this is the batch-mapping equivalent of the marker approach
    // used everywhere else, but sidesteps the fact that batch mappings can't
    // reliably pass state back through `context` (Apollo Server shallow-
    // clones it before handing it to resolvers, breaking the DataLoader
    // closure's view of any mutation). Throwing here rejects the whole
    // field for every parent in the batch.
    if (operation === 'Team.members') {
      const role = args[0];
      if (role !== 'auth') {
        throw new Error(`Access denied: role "${role}" is not permitted`);
      }
      return;
    }

    // Mapping/batch fields and zero-arg operations (like a subscription with
    // no arguments) always have an empty `args` array — there's nothing to
    // type-check there, so the marker fires unconditionally; a root
    // operation with declared arguments only fires when the first one is a
    // string (the thing the tests actually assert on).
    if ((args.length === 0 || typeof args[0] === 'string') && context) {
      context.marker = '(runBefore)';
    }
  }
}
