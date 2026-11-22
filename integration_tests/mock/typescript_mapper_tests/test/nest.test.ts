import { UserEntityMapper } from '../lib/generated_nest/mappers/user-entity-mapper';
import { UserMapper } from '../lib/generated_nest/mappers/user-mapper';
import { describeMappers } from './shared';

describeMappers('nest', { UserEntityMapper, UserMapper });
