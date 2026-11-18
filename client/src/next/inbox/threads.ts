import type { CorrespondenceMessage, Reply } from '../../api/types';

export type Entry = { kind: 'message'; at: string; message: CorrespondenceMessage } | { kind: 'reply'; at: string; reply: Reply };

export interface Thread {
  key: string;
  with: string;
  entries: Entry[];
}

const threadOf = (platform: string, thread: string | null, who: string) => thread ? `${platform}#${thread}` : `${platform}:${who.toLowerCase()}`;

export function threads(messages: CorrespondenceMessage[], replies: Reply[]): Thread[] {
  const byKey = new Map<string, Thread>();
  const byNumber = new Map(messages.map((m) => [m.number, m]));
  const add = (key: string, who: string, e: Entry) => {
    const t = byKey.get(key) ?? { key, with: who, entries: [] };
    t.entries.push(e);
    byKey.set(key, t);
  };
  for (const m of messages) add(threadOf(m.platform, m.thread, m.sender), m.sender_name ?? m.sender, { kind: 'message', at: m.sent_at, message: m });
  for (const r of replies) {
    if (r.state === 'superseded') continue;
    const origin = r.in_reply_to ? byNumber.get(r.in_reply_to) : undefined;
    const key = origin ? threadOf(origin.platform, origin.thread, origin.sender) : threadOf(r.platform, r.thread, r.to);
    add(key, origin ? (origin.sender_name ?? origin.sender) : r.to, { kind: 'reply', at: r.sent_at ?? r.drafted_at, reply: r });
  }
  const list = [...byKey.values()];
  for (const t of list) t.entries.sort((a, b) => a.at.localeCompare(b.at));
  return list.sort((a, b) => b.entries[b.entries.length - 1].at.localeCompare(a.entries[a.entries.length - 1].at));
}
