import { useState } from 'react';
import * as css from './time.css';

export interface JournalEntry {
  number: number;
  kind: string;
  register: string | null;
  text: string;
  at: string;
  by: string;
  done_at: string | null;
}

export type JournalOrder = 'kind' | 'oldest' | 'newest';

const KINDS = ['plan', 'note', 'todo', 'wrap'];
const rank = (kind: string) => (KINDS.includes(kind) ? KINDS.indexOf(kind) : KINDS.length);

/** The entries a filter and an order leave: by kind (plan, note, todo, wrap), or by when she wrote them. */
export function arrange(entries: JournalEntry[], kind: string | null, query: string, order: JournalOrder): JournalEntry[] {
  const q = query.trim().toLowerCase();
  const kept = entries.filter((e) => (kind === null || e.kind === kind) && (q === '' || e.text.toLowerCase().includes(q)));
  const at = (e: JournalEntry) => new Date(e.at).getTime();
  return kept.slice().sort((a, b) => {
    if (order === 'kind') return rank(a.kind) - rank(b.kind) || a.number - b.number;
    return order === 'oldest' ? at(a) - at(b) || a.number - b.number : at(b) - at(a) || b.number - a.number;
  });
}

const clock = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

/**
 * Her journal for one day, with a search over the words, a filter by
 * kind and an order: a day of rounds can hold dozens of notes.
 */
export function Journal({ name, entries }: { name: string; entries: JournalEntry[] }) {
  const [kind, setKind] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [order, setOrder] = useState<JournalOrder>('kind');
  const counts = new Map<string, number>();
  for (const e of entries) counts.set(e.kind, (counts.get(e.kind) ?? 0) + 1);
  const kinds = [...counts.keys()].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
  const shown = arrange(entries, kind, query, order);
  // The tools earn their room only once there is something to sift.
  const tools = entries.length > 3;

  return (
    <section className={css.journal}>
      <h2 className={css.headingHers}>
        {name.toUpperCase()}'S JOURNAL
        {entries.length > 0 ? ` · ${shown.length === entries.length ? entries.length : `${shown.length} OF ${entries.length}`}` : ''}
      </h2>
      {entries.length === 0 && <p className={css.note}>Nothing written this day.</p>}
      {tools && (
        <div className={css.journalTools}>
          <input
            className={css.journalSearch}
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search the day's entries"
            aria-label="Search the day's entries"
          />
          <div className={css.journalFilters}>
            <div className={css.chips} role="group" aria-label="Kind">
              <button type="button" className={css.chip} aria-pressed={kind === null} onClick={() => setKind(null)}>
                All
              </button>
              {kinds.map((k) => (
                <button key={k} type="button" className={css.chip} aria-pressed={kind === k} onClick={() => setKind(kind === k ? null : k)}>
                  {k[0].toUpperCase() + k.slice(1)} {counts.get(k)}
                </button>
              ))}
            </div>
            <select className={css.journalOrder} value={order} onChange={(e) => setOrder(e.target.value as JournalOrder)} aria-label="Order">
              <option value="kind">By kind</option>
              <option value="oldest">Oldest first</option>
              <option value="newest">Newest first</option>
            </select>
          </div>
        </div>
      )}
      {entries.length > 0 && shown.length === 0 && <p className={css.note}>No entry matches.</p>}
      {shown.map((e) => (
        <div key={e.number} className={css.entry}>
          <span className={css.entryKind}>
            {e.kind.toUpperCase()}
            <span className={css.entryAt}>{clock(e.at)}</span>
          </span>
          <span className={css.entryText} data-done={!!e.done_at}>
            {e.text}
          </span>
        </div>
      ))}
    </section>
  );
}
