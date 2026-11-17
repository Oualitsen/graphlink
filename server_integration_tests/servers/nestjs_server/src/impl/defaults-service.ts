import { ConfigService } from '../generated/services/config-service.js';
import { RangeService } from '../generated/services/range-service.js';
import { GreetService } from '../generated/services/greet-service.js';
import { EchoPriorityService } from '../generated/services/echo-priority-service.js';
import { AckPriorityService } from '../generated/services/ack-priority-service.js';
import { ConfigInput } from '../generated/inputs/config-input.js';
import { RangeInput } from '../generated/inputs/range-input.js';
import { Config } from '../generated/types/config.js';
import { Range } from '../generated/types/range.js';
import { Priority } from '../generated/enums/priority.js';

/**
 * Default/initial-value resolvers: each simply reflects its effective input back,
 * so a client that omits a defaulted field/argument can assert the schema default
 * was applied end-to-end.
 */
export class DefaultsServiceImpl
  implements ConfigService, RangeService, GreetService, EchoPriorityService, AckPriorityService
{
  async resolveConfig(input: ConfigInput): Promise<Config> {
    return {
      pageSize: input.pageSize!,
      ratio: input.ratio!,
      sort: input.sort!,
      verbose: input.verbose!,
      priority: input.priority!,
      tags: input.tags!,
      empties: input.empties!,
      note: input.note ?? null,
    };
  }

  async resolveRange(input: RangeInput | null): Promise<Range> {
    return { min: input?.min ?? 0, max: input?.max ?? 100 };
  }

  async greet(name: string | null, times: number | null): Promise<string> {
    return `Hi ${name}!`.repeat(times ?? 1);
  }

  async echoPriority(level: Priority | null): Promise<Priority> {
    return level ?? Priority.High;
  }

  async ackPriority(_level: Priority): Promise<string> {
    return 'OK';
  }
}
