// Domains in the chat (P23-R1, kumbukumbu#72): which messages open a new
// stretch of a domain, which domains this conversation has named, and
// what a slug may be. Pure, so the rules are tested apart from the view.
import type { Domain, Message } from '../../api/types';

/** A domain's slug: a letter, then letters, digits or hyphens, 2 to 32 in all (the server's rule). */
export const SLUG = /^[a-z][a-z0-9-]{1,31}$/;

export const slugOf = (d: Domain | null | undefined): string | null => d?.slug ?? null;

/**
 * The indexes of the messages where the domain changes from the one
 * before (her words and his alone; tool and system lines carry none of
 * their own): a rule is drawn above each, naming the domain it opens. The
 * first message is one when it is in a domain.
 */
export function domainBreaks(messages: Message[]): Map<number, string | null> {
  const breaks = new Map<number, string | null>();
  let last: string | null | undefined = undefined;
  messages.forEach((m, i) => {
    if (m.role !== 'user' && m.role !== 'assistant') return;
    const slug = slugOf(m.domain);
    if (last === undefined ? slug !== null : slug !== last) breaks.set(i, slug);
    last = slug;
  });
  return breaks;
}

/** The domains this conversation has named, newest first, the current one leading. */
export function knownDomains(messages: Message[], now: Domain | null): string[] {
  const seen: string[] = [];
  const add = (s: string | null) => {
    if (s && !seen.includes(s)) seen.push(s);
  };
  add(slugOf(now));
  for (let i = messages.length - 1; i >= 0; i--) add(slugOf(messages[i].domain));
  return seen;
}

/** What the composer's chip says: the domain the next message goes in. */
export function chipLabel(picked: string | null | undefined, now: Domain | null): string {
  const slug = picked === undefined ? slugOf(now) : picked;
  return slug ?? 'common room';
}
