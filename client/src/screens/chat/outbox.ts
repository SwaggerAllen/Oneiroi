// The outbox (brain#45): every message the witness sends is held here,
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
  // The turn it was answered in, when it joined another message's turn
  // (brain#66: what queued while a turn ran arrives together in the next).
  into?: string;
  // When it was first sent, and when its present state began (ms since
  // the epoch), for the timers the witness reads (brain#54).
  sentAt?: number;
  since?: number;
  // When it was last sent to the server, for the stuck check below.
  triedAt?: number;
}

// The states a turn is under way in: taken and not yet answered.
export const underWay: OutState[] = ['queued', 'running', 'thinking', 'tool', 'writing'];

export type Connection = 'connected' | 'connecting' | 'offline';

// A ref the server accepts: 8 to 64 of A-Z a-z 0-9 _ -.
export function newRef(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

// A change of state restarts the state's timer; the same state again
// (a retry answered as a duplicate, another round's `thinking`) keeps it.
// A turn's news is news for every message that went into it.
export function update(items: Outgoing[], ref: string, change: Partial<Outgoing>, now = Date.now()): Outgoing[] {
  return items.map((i) => {
    if (i.ref !== ref && i.into !== ref) return i;
    const moved = change.state !== undefined && change.state !== i.state;
    return { ...i, ...change, sentAt: i.sentAt ?? now, since: moved || i.since === undefined ? now : i.since };
  });
}

// The failures the server recorded (kumbukumbu capture failures), read
// back so a failure broadcast while the page was away is not missed: a
// message under way whose turn failed says so (brain#54).
export function failedFrom(items: Outgoing[], failures: { turn_ref: string; reason: string }[], now = Date.now()): Outgoing[] {
  const by = new Map(failures.map((f) => [f.turn_ref, f.reason]));
  return items.reduce<Outgoing[]>((out, i) => {
    const reason = by.get(i.ref) ?? (i.into !== undefined ? by.get(i.into) : undefined);
    return reason !== undefined && i.state !== 'failed' ? update(out, i.ref, { state: 'failed', error: reason }, now) : out;
  }, items);
}

// A failure the provider refused for credit (brain#88): it needs him to
// top up the account, not to send again.
export function creditRefusal(reason: string | null | undefined): boolean {
  return !!reason && reason.includes('402') && reason.toLowerCase().includes('credit');
}

// What a failure says in the chat: the provider's own words, with the
// status code and error kind trimmed off the front.
export function failureWords(reason: string | null | undefined): string {
  if (!reason) return 'the turn failed';
  return reason.replace(/^nisaba_[a-z_]+:\s*/, '').replace(/^\d{3}\s+/, '');
}

// How long, said short: 42s, 3m 05s, 1h 02m.
export function elapsed(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${String(s % 60).padStart(2, '0')}s`;
  return `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`;
}

// How long a message may sit taken but unheard of before it is sent
// again: past the server's turn timeout (BRAIN_TURN_TIMEOUT_MS, 300s),
// when a claim that died with a restart is taken again (brain#45).
export const STUCK_MS = 330_000;

// Messages that were taken and then nothing more was heard of them: a
// queue lost to a restart, or a send the server answered as a duplicate
// of a claim that died. Sending one again under its own ref is safe
// either way: a turn still alive answers it as a duplicate, a dead claim
// past the timeout is taken again. One that joined another's turn goes
// with that turn and is never sent alone.
export function stuck(items: Outgoing[], now = Date.now(), after = STUCK_MS): Outgoing[] {
  return items.filter(
    (i) => i.into === undefined && (i.state === 'sending' || underWay.includes(i.state)) && now - (i.triedAt ?? i.since ?? i.sentAt ?? now) >= after,
  );
}

// The witness takes a message off this screen (the fallback when one
// will not settle). It is this browser's copy only: a message the server
// still holds may yet run, and its turn lands in the transcript if so.
export function remove(items: Outgoing[], ref: string): Outgoing[] {
  return items.filter((i) => i.ref !== ref);
}

// A message is done when its turn is in the transcript with a reply.
export function settle(items: Outgoing[], answered: Set<string>): Outgoing[] {
  return items.filter((i) => !answered.has(i.ref) && !(i.into !== undefined && answered.has(i.into)));
}

// A message that joined another's turn (brain#66): it runs with it from here.
export function batched(items: Outgoing[], ref: string, into: string, now = Date.now()): Outgoing[] {
  return items.map((i) => (i.ref === ref ? { ...i, into, state: 'running', since: now, sentAt: i.sentAt ?? now } : i));
}

// What the resident is doing now, for the header: the newest message
// that is still on its way says it.
// Each says how long it has been so (brain#54), and, once that differs,
// how long since the message went.
export function statusLine(items: Outgoing[], name: string, now = Date.now()): string | null {
  const live = [...items].reverse().find((i) => i.state !== 'failed' && i.state !== 'unsent');
  if (!live) return null;
  const words = stateWords(live, name);
  if (!words || live.since === undefined) return words;
  const sent = live.sentAt !== undefined && live.since - live.sentAt >= 5_000 ? ` · sent ${elapsed(now - live.sentAt)} ago` : '';
  return `${words} ${elapsed(now - live.since)}${sent}`;
}

function stateWords(live: Outgoing, name: string): string | null {
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
