import { UserEntityMapper } from '../lib/generated_express/mappers/user-entity-mapper';
import { UserMapper } from '../lib/generated_express/mappers/user-mapper';
import { describeMappers } from './shared';

describeMappers('express', { UserEntityMapper, UserMapper });
