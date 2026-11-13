// The search sheet's filters (kumbukumbu#67, #69; the witness, 2026-11-12):
// each scope's own narrowing, behind a Filter button, as query parameters.
import { dayStart } from './dayStart';

export type Sort = 'relevance' | 'newest' | 'oldest';

export interface Filters {
  from: string; // YYYY-MM-DD, this browser's zone, included
  to: string; // YYYY-MM-DD, included
  date: 'created' | 'updated'; // records: registration or last write
  sort: Sort;
  // Records
  kinds: string[];
  status: string;
  author: '' | 'resident' | 'witness' | 'platform';
  // Transcripts
  who: '' | 'resident' | 'witness' | 'platform';
  sentTo: '' | 'resident' | 'witness';
  conversations: string[];
  // Letters
  letterFrom: string;
  letterTo: string;
  // Bookmarks
  pinned: boolean;
  tag: string;
  madeBy: '' | 'resident' | 'witness';
  // Scenes
  mood: string;
  person: string;
}

export const NO_FILTERS: Filters = {
  from: '',
  to: '',
  date: 'updated',
  sort: 'relevance',
  kinds: [],
  status: '',
  author: '',
  who: '',
  sentTo: '',
  conversations: [],
  letterFrom: '',
  letterTo: '',
  pinned: false,
  tag: '',
  madeBy: '',
  mood: '',
  person: '',
};

/** The scopes that take filters; everything and as-she-sees-it do not. */
export const FILTERED = ['records', 'bookmarks', 'scenes', 'words', 'letters'] as const;

export const CONVERSATIONS: Array<[string, string]> = [
  ['main', 'Main chat'],
  ['free_time', 'Free time'],
  ['round', 'Rounds'],
  ['work', 'Work'],
  ['housekeeping', 'Housekeeping'],
  ['hands', 'Hands'],
  ['adapter', 'Adapters'],
  ['imported', 'Imported'],
];

/** The orders a scope offers: transcripts are newest or oldest; the rest rank first. */
export function sorts(scope: string): Sort[] {
  return scope === 'words' || scope === 'letters' ? ['newest', 'oldest'] : ['relevance', 'newest', 'oldest'];
}

/** How many filters are set for a scope, for the button's count. */
export function activeCount(scope: string, f: Filters): number {
  const own: Record<string, unknown[]> = {
    records: [f.kinds.length > 0, f.status, f.author],
    words: [f.who, f.sentTo, f.conversations.length > 0],
    letters: [f.letterFrom, f.letterTo],
    bookmarks: [f.pinned, f.tag, f.madeBy],
    scenes: [f.mood, f.person],
  };
  return [f.from, f.to, ...(own[scope] ?? [])].filter(Boolean).length;
}

/** The query parameters for a scope: only what is set, in the server's names. */
export function toParams(scope: string, f: Filters, page = 1): Record<string, string> {
  if (!(FILTERED as readonly string[]).includes(scope)) return {};
  const out: Record<string, string> = {};
  const from = dayStart(f.from, 0);
  const to = dayStart(f.to, 1);
  if (from) out.from = from;
  if (to) out.to = to;
  const sort = sorts(scope).includes(f.sort) ? f.sort : sorts(scope)[0];
  if (scope === 'words') {
    out.page = String(page);
    out.sort = sort;
    if (f.who) out.who = f.who;
    if (f.sentTo) out.sent_to = f.sentTo;
    if (f.conversations.length) out.conversations = f.conversations.join(',');
    return out;
  }
  if (scope === 'letters') {
    out.sort = sort;
    if (f.letterFrom) out.written_by = f.letterFrom;
    if (f.letterTo) out.sent_to = f.letterTo;
    return out;
  }
  if (sort !== 'relevance') out.sort = sort;
  if (scope === 'records') {
    if (from || to) out.date = f.date;
    if (f.kinds.length) out.kinds = f.kinds.join(',');
    if (f.status.trim()) out.status = f.status.trim();
    if (f.author) out.author = f.author;
  }
  if (scope === 'bookmarks') {
    if (f.pinned) out.pinned = 'true';
    if (f.tag) out.tag = f.tag;
    if (f.madeBy) out.made_by = f.madeBy;
  }
  if (scope === 'scenes') {
    if (f.mood.trim()) out.mood = f.mood.trim();
    if (f.person.trim()) out.person = f.person.trim();
  }
  return out;
}
