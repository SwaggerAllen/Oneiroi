import type { NeedsYouEntry } from '../../api/types';

// What waits on you, as the screen says it (screens/inbox.md): the
// server's `needs_you` list (brain#65), oldest first, each entry a line
// and the place its decision is made. It only shows: every decision is
// made where the thing is, by your click, always. Nothing is sent on a
// timeout and nothing is approved ahead; an old one is marked, never
// acted on.
export interface WaitingEntry {
  key: string;
  what: string;
  since: string;
  long: boolean;
  // Where its decision is made: an anchor on this screen, or a screen's name.
  // A document's own page (#doc/<path>) for a piece: the decision sits
  // beside its words there (Lily's letter #338).
  where: { anchor: string } | { screen: string } | { doc: string };
}

function line(residentName: string, e: NeedsYouEntry): string {
  const a = e.about;
  switch (e.kind) {
    case 'reply_to_approve':
      return `Approve or decline ${residentName}’s reply #${e.ref} to ${a.to} on ${a.platform}`;
    case 'reply_to_send':
      return `Send reply #${e.ref} to ${a.to} on ${a.platform}, approved`;
    case 'ask':
      return `${residentName} asks: ${a.subject}`;
    case 'piece_to_review':
      return `Review the piece ${a.title ?? e.ref}`;
    case 'piece_to_publish':
      return `Publish the drafted piece ${a.title ?? e.ref}`;
    case 'work_blocked':
      return `Work item #${e.ref} blocked${a.blocked_on ? ` on ${a.blocked_on}` : ''}: ${a.what}`;
    case 'plugin_proposal':
      return `${residentName} proposes to ${a.change} the plugin ${a.key}: ${a.note}`;
  }
}

function where(e: NeedsYouEntry): WaitingEntry['where'] {
  if (e.screen === 'schedule') return { screen: 'Schedule' };
  if (e.screen === 'work') return { screen: 'Work' };
  if (e.screen === 'agreement') return { screen: 'Agreement' };
  if (e.kind === 'ask') return { anchor: 'asks' };
  if (e.kind === 'piece_to_review' || e.kind === 'piece_to_publish') return { doc: String(e.ref) };
  return { anchor: `reply-${e.ref}` };
}

export function waitingEntries(residentName: string, entries: NeedsYouEntry[]): WaitingEntry[] {
  return entries.map((e) => ({ key: `${e.kind}:${e.ref}`, what: line(residentName, e), since: e.since, long: e.long, where: where(e) }));
}

export function age(since: string, now: number): string {
  const hours = Math.floor(Math.max(0, now - Date.parse(since)) / 3600_000);
  if (hours < 1) return 'under an hour';
  if (hours < 48) return `${hours} hour${hours === 1 ? '' : 's'}`;
  return `${Math.floor(hours / 24)} days`;
}
