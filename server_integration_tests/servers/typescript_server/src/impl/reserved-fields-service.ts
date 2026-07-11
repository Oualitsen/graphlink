import { ReservedFieldsService } from '../generated/services/reserved-fields-service.js';
import { ReservedFields } from '../generated/types/reserved-fields.js';
import { ReservedInput } from '../generated/inputs/reserved-input.js';
import { Keyword } from '../generated/enums/keyword.js';

export class ReservedFieldsServiceImpl implements ReservedFieldsService {
  private base(): ReservedFields {
    return {
      id: 'r1',
      class: 'cls',
      return: 42,
      new: true,
      default: 'def',
      is: 'yes',
      in: 'inside',
      with: 'w',
      int: 7,
      synchronized: false,
      native: 'n',
      kind: Keyword.Class,
      nested: { id: 'c1', value: 'v' },
      secret: { id: 's1', token: 'tok' },
    };
  }

  async reserved(): Promise<ReservedFields> {
    return this.base();
  }

  async switch(class_: string, return_: number | null): Promise<ReservedFields> {
    return { ...this.base(), class: class_, return: return_ ?? 0 };
  }

  async echoReserved(input: ReservedInput): Promise<ReservedFields> {
    return {
      ...this.base(),
      class: input.class,
      return: input.return ?? -1,
      default: input.default ?? 'none',
    };
  }
}
