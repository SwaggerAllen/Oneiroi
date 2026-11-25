// The agreement's domain terms: who a domain's person is, and the
// declared domains' policies (agathos-daimon#53, #57). Walls are retired
// (agathos-daimon#58).
import type { ContractTerms, DomainPolicy } from '../../api/client';

export type Who = 'witness' | 'resident' | 'anyone';

export interface Persons {
  witness: string | null;
  resident: string;
}

/** Who a person is, read off the agreement's persons. */
export function whoOf(person: string, persons: Persons): Who | 'other' {
  if (person === '*') return 'anyone';
  if (person === persons.witness) return 'witness';
  if (person === persons.resident) return 'resident';
  return 'other';
}

export function personOf(who: Who, persons: Persons): string | null {
  if (who === 'anyone') return '*';
  return who === 'witness' ? persons.witness : persons.resident;
}

/**
 * The terms with these domain policies, the switches kept; none drops the
 * key. A version is the whole agreement, so the policies in force ride
 * every version unless changed (agathos-daimon#53).
 */
export function withPolicies(terms: Record<string, boolean>, policies: DomainPolicy[] = []): ContractTerms {
  const out: ContractTerms = { ...terms };
  if (policies.length) out.domain_policies = policies.map(wirePolicy);
  return out;
}

// The wire shape a policy is agreed in: its own fields, nothing the read added.
const wirePolicy = (p: DomainPolicy): DomainPolicy => ({
  domain: { person: p.domain.person, domain: p.domain.domain },
  ...(p.description?.trim() ? { description: p.description.trim() } : {}),
  default: p.default,
  allow: p.allow.map((g) => ({ kind: g.kind, id: g.id })),
  deny: p.deny.map((g) => ({ kind: g.kind, id: g.id })),
});

/** The longest a domain's description may be (agathos-daimon#62). */
export const DESCRIPTION_LIMIT = 300;

export const samePolicyDomain = (a: DomainPolicy, b: DomainPolicy) =>
  a.domain.person === b.domain.person && a.domain.domain === b.domain.domain;

/** A declared domain in words: whose life, its default, and who it reaches beyond that. */
export function policyWords(p: DomainPolicy, persons: Persons, name: string): string {
  if (p.domain.person === '*' && p.domain.domain === 'common-room') return roomWords(p);
  const who = whoOf(p.domain.person, persons);
  const whose = who === 'witness' ? 'your' : who === 'resident' ? `${name}'s` : who === 'anyone' ? "anyone's" : "another person's";
  const grants = (gs: { kind: string; id: string }[]) => gs.map((g) => `${g.kind}:${g.id}`).join(', ');
  const allow = p.allow.length ? `; allows ${grants(p.allow)}` : '';
  const deny = p.deny.length ? `; denies ${grants(p.deny)}` : '';
  const covers = p.description?.trim() ? ` (${p.description.trim()})` : '';
  return `${whose} ${p.domain.domain}${covers}: ${p.default === 'allow' ? 'reaches any audience by default' : 'reaches no audience past you two by default'}${allow}${deny}`;
}

const grantList = (gs: { kind: string; id: string }[]) => gs.map((g) => `${g.kind}:${g.id}`).join(', ');

/** The common room's written policy in words (kumbukumbu#97). */
function roomWords(p: DomainPolicy): string {
  const allow = p.allow.length ? `; allows ${grantList(p.allow)}` : '';
  const deny = p.deny.length ? `; denies ${grantList(p.deny)}` : '';
  return `the common room: ${p.default === 'allow' ? 'reaches any audience by default' : 'reaches no audience past you two by default'}${allow}${deny}`;
}
