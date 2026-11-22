import { describe, expect, it } from 'vitest';
import { personOf, policyWords, whoOf, withPolicies } from './terms';

const persons = { witness: 'account:a', resident: 'resident:r' };

describe('the agreement\'s domain terms', () => {
  it('reads who a person is and writes them back', () => {
    expect(whoOf('account:a', persons)).toBe('witness');
    expect(whoOf('*', persons)).toBe('anyone');
    expect(whoOf('account:z', persons)).toBe('other');
    expect(personOf('resident', persons)).toBe('resident:r');
    expect(personOf('anyone', persons)).toBe('*');
  });

  it('says the common room\'s written policy as the common room (kumbukumbu#97)', () => {
    const room = { domain: { person: '*', domain: 'common-room' }, default: 'deny' as const, allow: [{ kind: 'household', id: '*' }], deny: [] };
    expect(policyWords(room, persons, 'Lily')).toBe('the common room: reaches no audience past you two by default; allows household:*');
  });

  it('carries the declared domains and their policies into every version (agathos-daimon#53, #57), and no walls (#58)', () => {
    const policy = { domain: { person: 'account:a', domain: 'recovery' }, default: 'deny' as const, allow: [{ kind: 'household', id: '*' }], deny: [] };
    expect(withPolicies({ x: true }, [policy])).toEqual({ x: true, domain_policies: [policy] });
    expect(withPolicies({ x: true }, [])).toEqual({ x: true });
  });
});
