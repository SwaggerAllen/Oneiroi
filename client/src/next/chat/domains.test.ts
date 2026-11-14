import { describe, expect, it } from 'vitest';
import type { Message } from '../../api/types';
import { chipLabel, domainBreaks, knownDomains, SLUG } from './domains';

const him = 'account:00000000-0000-0000-0000-000000000000';
const msg = (i: number, role: string, slug: string | null): Message => ({
  session_key: 'k',
  turn_ref: `t${i}`,
  role,
  content: `m${i}`,
  sent_at: '2026-11-13T12:00:00Z',
  actor: { kind: role === 'user' ? 'witness' : 'resident', id: 'x', model: null },
  refusal: false,
  domain: slug ? { slug, person: him } : null,
});

describe('domains in the chat (kumbukumbu#72)', () => {
  it('draws a rule where the domain changes, her words and his alone', () => {
    const messages = [msg(0, 'user', null), msg(1, 'assistant', null), msg(2, 'user', 'business'), msg(3, 'tool', null), msg(4, 'assistant', 'business'), msg(5, 'user', 'recovery'), msg(6, 'user', null)];
    expect([...domainBreaks(messages)]).toEqual([
      [2, 'business'],
      [5, 'recovery'],
      [6, null],
    ]);
    // A page opening inside a domain says so at its first message.
    expect([...domainBreaks([msg(0, 'user', 'business')])]).toEqual([[0, 'business']]);
  });

  it('lists the domains named, the current one first', () => {
    const messages = [msg(0, 'user', 'family'), msg(1, 'user', 'business'), msg(2, 'user', 'family')];
    expect(knownDomains(messages, { slug: 'recovery', person: him })).toEqual(['recovery', 'family', 'business']);
    expect(knownDomains([], null)).toEqual([]);
  });

  it('says where the next message goes', () => {
    expect(chipLabel(undefined, { slug: 'business', person: him })).toBe('business');
    expect(chipLabel(null, { slug: 'business', person: him })).toBe('common room');
    expect(chipLabel('recovery', null)).toBe('recovery');
    expect(chipLabel(undefined, null)).toBe('common room');
  });

  it('takes the server’s slug rule', () => {
    expect(SLUG.test('recovery')).toBe(true);
    expect(SLUG.test('r')).toBe(false);
    expect(SLUG.test('Recovery')).toBe(false);
    expect(SLUG.test('in-person')).toBe(true);
  });
});
