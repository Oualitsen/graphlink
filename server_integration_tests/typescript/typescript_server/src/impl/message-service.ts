import { MessageService } from '../generated/services/message-service.js';
import { MessageReadSchemaMappingsService } from '../generated/services/message-read-schema-mappings-service.js';
import { Message } from '../generated/types/message.js';

export class MessageServiceImpl implements MessageService, MessageReadSchemaMappingsService {
  async getMessageReadList(): Promise<(Message | null)[] | null> {
    return [
      { id: 'm1', content: 'hello' },
      { id: 'm2', content: 'world' },
    ];
  }

  async messageReadRead(value: Message[]): Promise<Map<Message, boolean>> {
    const result = new Map<Message, boolean>();
    for (const m of value) {
      result.set(m, m.id.endsWith('1'));
    }
    return result;
  }
}
