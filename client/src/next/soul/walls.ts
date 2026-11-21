// The domain walls (agathos-daimon#45, P23-R1 §3): contract terms both of
// you agree, each closing the door retrieval would name from one domain
// into one context. Never her reach: she still opens what is walled.
import type { ContractTerms, DomainPolicy, DomainWall } from '../../api/client';

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

const whose = (who: Who | 'other', name: string) => (who === 'witness' ? 'your' : who === 'resident' ? `${name}'s` : who === 'anyone' ? "anyone's" : "another person's");

/** A wall in a sentence: whose domain, never named into what. */
export function wallWords(w: DomainWall, persons: Persons, name: string): string {
  const from = `${whose(whoOf(w.memory.person, persons), name)} ${w.memory.domain}`;
  const c = w.context;
  const to =
    c.person === '*' && c.domain === '*'
      ? 'any other context'
      : c.domain === '*'
        ? `anything of ${whose(whoOf(c.person, persons), name).replace(/^your$/, 'yours')}`
        : `${whose(whoOf(c.person, persons), name)} ${c.domain}`;
  return `${from} is never named into ${to}`;
}

/** A version's walls, from its terms. */
export function wallsOf(terms: ContractTerms | undefined): DomainWall[] {
  const walls = terms?.domain_walls;
  return Array.isArray(walls) ? (walls as DomainWall[]) : [];
}

/**
 * The terms with these walls and these domain policies, the switches
 * kept; none drops the key. A version is the whole agreement, so the
 * policies in force ride every version unless changed (agathos-daimon#53).
 */
export function withWalls(terms: Record<string, boolean>, walls: DomainWall[], policies: DomainPolicy[] = []): ContractTerms {
  const out: ContractTerms = { ...terms };
  if (walls.length) out.domain_walls = walls;
  if (policies.length) out.domain_policies = policies.map(wirePolicy);
  return out;
}

// The wire shape a policy is agreed in: its own fields, nothing the read added.
const wirePolicy = (p: DomainPolicy): DomainPolicy => ({
  domain: { person: p.domain.person, domain: p.domain.domain },
  default: p.default,
  allow: p.allow.map((g) => ({ kind: g.kind, id: g.id })),
  deny: p.deny.map((g) => ({ kind: g.kind, id: g.id })),
});

export const samePolicyDomain = (a: DomainPolicy, b: DomainPolicy) =>
  a.domain.person === b.domain.person && a.domain.domain === b.domain.domain;

/** A declared domain in words: whose life, its default, and who it reaches beyond that. */
export function policyWords(p: DomainPolicy, persons: Persons, name: string): string {
  const who = whoOf(p.domain.person, persons);
  const whose = who === 'witness' ? 'your' : who === 'resident' ? `${name}'s` : who === 'anyone' ? "anyone's" : "another person's";
  const grants = (gs: { kind: string; id: string }[]) => gs.map((g) => `${g.kind}:${g.id}`).join(', ');
  const allow = p.allow.length ? `; allows ${grants(p.allow)}` : '';
  const deny = p.deny.length ? `; denies ${grants(p.deny)}` : '';
  return `${whose} ${p.domain.domain}: ${p.default === 'allow' ? 'reaches any audience by default' : 'reaches no audience past you two by default'}${allow}${deny}`;
}

export const sameWall = (a: DomainWall, b: DomainWall) =>
  a.memory.person === b.memory.person && a.memory.domain === b.memory.domain && a.context.person === b.context.person && a.context.domain === b.context.domain;
