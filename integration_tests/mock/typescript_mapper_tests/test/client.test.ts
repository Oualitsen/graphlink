import { UserEntityMapper } from '../lib/generated/mappers/user-entity-mapper';
import { UserMapper } from '../lib/generated/mappers/user-mapper';
import { describeMappers } from './shared';

describeMappers('client', { UserEntityMapper, UserMapper });
