import { TeamService } from '../generated/services/team-service.js';
import { TeamSchemaMappingsService } from '../generated/services/team-schema-mappings-service.js';
import { Team } from '../generated/types/team.js';
import { Member } from '../generated/types/member.js';

const teams: Team[] = [{ id: '1', name: 'Core' }];

const membersByTeamId: Record<string, Member[]> = {
  '1': [{ id: '1', name: 'Ada' }, { id: '2', name: 'Grace' }],
};

export class TeamServiceImpl implements TeamService {
  async listTeams(): Promise<Team[]> {
    return teams;
  }
}

export class TeamSchemaMappingsServiceImpl implements TeamSchemaMappingsService {
  // Access control lives entirely in InterceptorImpl.runBefore (throw to
  // deny, return to allow) — by the time this method runs, the caller was
  // already let through, so it just returns the real data.
  async teamMembers(role: string, value: Team): Promise<Member[]> {
    return membersByTeamId[value.id] ?? [];
  }
}
