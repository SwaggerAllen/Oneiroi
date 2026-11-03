// The outbox (brain #45): every message the witness sends is held here,
// under the client's own ref, until its turn lands in the transcript. A
// message the server never acknowledged can be sent again under the same
// ref, and the server answers a ref it has already taken as a duplicate,
// so a retry never runs a turn twice. Nothing here is the record; the
// transcript is.

export type OutState =
  | 'sending' // on its way, not yet acknowledged
  | 'unsent' // never acknowledged: sent again under the same ref
  | 'queued' // taken, waiting behind another turn
  | 'running' // taken, the turn has started
  | 'thinking' // the model is being asked
  | 'tool' // a tool is running; `detail` names it
  | 'writing' // the reply is streaming
  | 'failed'; // the turn ran and no reply came; the words were kept

export interface Outgoing {
  ref: string;
  text: string;
  state: OutState;
  detail?: string;
  // Why it failed or went unsent, in the server's words when it gave any.
  error?: string;
  attempts: number;
}

export type Connection = 'connected' | 'connecting' | 'offline';

// A ref the server accepts: 8 to 64 of A-Z a-z 0-9 _ -.
export function newRef(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function update(items: Outgoing[], ref: string, change: Partial<Outgoing>): Outgoing[] {
  return items.map((i) => (i.ref === ref ? { ...i, ...change } : i));
}

// A message is done when its turn is in the transcript with a reply.
export function settle(items: Outgoing[], answered: Set<string>): Outgoing[] {
  return items.filter((i) => !answered.has(i.ref));
}

// What the resident is doing now, for the header: the newest message
// that is still on its way says it.
export function statusLine(items: Outgoing[], name: string): string | null {
  const live = [...items].reverse().find((i) => i.state !== 'failed' && i.state !== 'unsent');
  if (!live) return null;
  switch (live.state) {
    case 'sending':
      return 'Sending…';
    case 'queued':
      return `Queued: ${name} is finishing another reply`;
    case 'running':
    case 'thinking':
      return `${name} is thinking…`;
    case 'tool':
      return `${name} is using ${live.detail ?? 'a tool'}…`;
    case 'writing':
      return `${name} is writing…`;
    default:
      return null;
  }
}

// The words under a message the witness sent, saying where it is.
export function itemLine(item: Outgoing, name: string): string {
  switch (item.state) {
    case 'sending':
      return 'sending…';
    case 'unsent':
      return item.error ? `not sent: ${item.error}` : 'not sent yet: no connection';
    case 'queued':
      return 'queued';
    case 'failed':
      return `${name} couldn't answer${item.error ? `: ${item.error}` : ''}`;
    default:
      return 'delivered';
  }
}

const storeKey = (session: string) => `oneiroi:outbox:${session}`;

// Kept in this browser so a reload does not lose a message on its way.
export function loadOutbox(session: string): Outgoing[] {
  try {
    const raw = localStorage.getItem(storeKey(session));
    return raw ? (JSON.parse(raw) as Outgoing[]) : [];
  } catch {
    return [];
  }
}

export function saveOutbox(session: string, items: Outgoing[]) {
  try {
    if (items.length === 0) localStorage.removeItem(storeKey(session));
    else localStorage.setItem(storeKey(session), JSON.stringify(items));
  } catch {
    // A browser that keeps nothing still has the outbox for this visit.
  }
}
