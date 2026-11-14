// The domain walls (agathos-daimon#45, P23-R1 §3): contract terms both of
// you agree, each closing the door retrieval would name from one domain
// into one context. Never her reach: she still opens what is walled.
import type { ContractTerms, DomainWall } from '../../api/client';

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
  return Array.isArray(walls) ? walls : [];
}

/** The terms with these walls, the switches kept; none drops the key. */
export function withWalls(terms: Record<string, boolean>, walls: DomainWall[]): ContractTerms {
  return walls.length === 0 ? { ...terms } : { ...terms, domain_walls: walls };
}

export const sameWall = (a: DomainWall, b: DomainWall) =>
  a.memory.person === b.memory.person && a.memory.domain === b.memory.domain && a.context.person === b.context.person && a.context.domain === b.context.domain;
