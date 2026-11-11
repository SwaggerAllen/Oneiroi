import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { Bookmark, RetrievalCount } from '../../api/types';
import { ScrollArea } from '../shell/ScrollArea';
import { formatHash } from '../state/routes';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { activeTags, filterBookmarks, listedBookmarks, spanWords, who, type MemoryView } from './bookmarks';
import * as mcss from './memory.css';
import { PageHead } from './NoteAction';
import { day } from './soul';
import * as css from './soul.css';

// Soul › Memory (`memory`), the old client's Memory screen ported
// (ui-structures.md D: Memory is not a place; this is a page on Soul's
// stack beside her pins). Her bookmarks newest first, by page; what is in
// front of her every turn, as the server words it, and what that leaves
// out; how retrieval has used each thing; a tag filter and a search; Pin
// and Unpin. One bookmark opens as `memory/<n>`.

const PAGE = 20;

// The view, tag and search outlive opening one bookmark and coming back
// (the list page is not mounted while the bookmark is on top), per resident.
type Kept = { view: MemoryView; tag: string | null; query: string };
const keptBy = new Map<string, Kept>();

export function Memory({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const kept = keptBy.get(id) ?? { view: 'index', tag: null, query: '' };
  const keep = (k: Partial<Kept>) => keptBy.set(id, { ...(keptBy.get(id) ?? kept), ...k });
  const [view, setViewState] = useState<MemoryView>(kept.view);
  const [tag, setTagState] = useState<string | null>(kept.tag);
  const [query, setQueryState] = useState(kept.query);
  const setView = (v: MemoryView) => (keep({ view: v }), setViewState(v));
  const setTag = (t: string | null) => (keep({ tag: t }), setTagState(t));
  const setQuery = (q: string) => (keep({ query: q }), setQueryState(q));

  const index = useQuery({ queryKey: ['resident', id, 'memory', 'index'], queryFn: () => api.indexNow(id) });
  // The whole list, shared with the root's pins: what the index and the pins name.
  const all = useQuery({ queryKey: ['resident', id, 'memory', 'bookmarks'], queryFn: () => api.bookmarks(id) });
  const pages = useInfiniteQuery({
    queryKey: ['resident', id, 'memory', 'pages'],
    queryFn: ({ pageParam }) => api.bookmarksPage(id, { limit: PAGE, before: pageParam }),
    initialPageParam: undefined as number | undefined,
    getNextPageParam: (last) => (last.more && last.bookmarks.length > 0 ? last.bookmarks[last.bookmarks.length - 1].number : undefined),
    enabled: view === 'all',
  });
  const tags = useQuery({ queryKey: ['resident', id, 'soul', 'tags'], queryFn: () => api.tags(id) });
  // Not every server answers this; the view shows only when it does.
  const retrieval = useQuery({ queryKey: ['resident', id, 'memory', 'retrieval'], queryFn: () => api.retrieval(id), retry: false });

  const listed = new Set(index.data?.listed ?? []);
  const source: Bookmark[] =
    view === 'index'
      ? listedBookmarks(index.data?.listed ?? [], all.data ?? [])
      : view === 'pinned'
        ? (all.data ?? []).filter((b) => b.pinned_at !== null).sort((a, b) => b.number - a.number)
        : (pages.data?.pages ?? []).flatMap((p) => p.bookmarks);
  const rows = filterBookmarks(source, tag, query);
  const pending = view === 'index' ? index.isPending || all.isPending : view === 'pinned' ? all.isPending : pages.isPending;
  const views: Array<{ v: MemoryView; label: string }> = [
    { v: 'index', label: `Every turn${index.data ? ` · ${index.data.listed.length}` : ''}` },
    { v: 'all', label: `All${all.data ? ` · ${all.data.length}` : ''}` },
    { v: 'pinned', label: 'Pinned' },
    ...(retrieval.data ? [{ v: 'use' as MemoryView, label: 'Use' }] : []),
  ];
  const tagSlugs = activeTags(tags.data ?? []);

  return (
    <ScrollArea label="Memory">
      <div className={css.page}>
        <PageHead title="Memory" lead={`What ${name} chose to keep: her bookmarks, what she sees every turn, and how retrieval has used them.`} onBack={onBack} />
        <div className={mcss.views} role="group" aria-label="View">
          {views.map(({ v, label }) => (
            <button key={v} type="button" className={view === v ? mcss.viewOn : mcss.view} aria-pressed={view === v} onClick={() => setView(v)}>
              {label}
            </button>
          ))}
        </div>

        {view === 'use' && retrieval.data ? (
          <Use name={name} rows={retrieval.data} />
        ) : (
          <>
            {view === 'index' && index.data && (
              <section className={css.section} aria-label="What she sees every turn">
                <p className={css.note}>{index.data.description}</p>
                <p className={css.meta}>
                  {index.data.listed.length} IN FRONT OF EVERY TURN · {index.data.left_out} LEFT OUT, RANKED PER TURN UNDER THE BUDGET
                  {index.data.elsewhere ? ` · ${index.data.elsewhere} ONLY IN THEIR ROOM` : ''}
                </p>
              </section>
            )}
            <input className={css.input} aria-label="Search bookmarks" placeholder="Search bookmarks" value={query} onChange={(e) => setQuery(e.target.value)} />
            {tagSlugs.length > 0 && (
              <div className={mcss.views} role="group" aria-label="Tag">
                {tagSlugs.map((slug) => (
                  <button key={slug} type="button" className={tag === slug ? mcss.viewOn : mcss.view} aria-pressed={tag === slug} onClick={() => setTag(tag === slug ? null : slug)}>
                    #{slug}
                  </button>
                ))}
              </div>
            )}
            {pending && <p className={css.note}>Reading…</p>}
            {!pending && rows.length === 0 && (
              <p className={css.note}>
                {all.data?.length === 0 ? `${name} has not bookmarked anything yet.` : view === 'index' ? 'Nothing is in front of every turn.' : 'Nothing here.'}
              </p>
            )}
            {rows.map((b) => (
              <Row key={b.number} b={b} inIndex={listed.has(b.number)} />
            ))}
            {view === 'all' && pages.hasNextPage && (
              <div className={css.buttons}>
                <button type="button" className={css.secondary} disabled={pages.isFetchingNextPage} onClick={() => void pages.fetchNextPage()}>
                  {pages.isFetchingNextPage ? 'Reading…' : 'Older bookmarks'}
                </button>
              </div>
            )}
            {view === 'all' && pages.hasNextPage && (tag || query.trim()) && (
              <p className={css.note}>The filter reads the bookmarks loaded so far; older ones may match too.</p>
            )}
          </>
        )}
      </div>
    </ScrollArea>
  );
}

function Row({ b, inIndex }: { b: Bookmark; inIndex: boolean }) {
  const { name } = useSubject();
  const push = useShell((s) => s.push);
  return (
    <div className={b.pinned_at ? css.cardHers : css.card}>
      <p className={css.meta}>
        #{b.number} · {day(b.anchor_at)} · {spanWords(b.turns_back).toUpperCase()}
        {b.pinned_at ? ` · PINNED BY ${who(b.pinned_by?.kind, name).toUpperCase()}` : ''}
        {inIndex ? ' · EVERY TURN' : ''}
      </p>
      {b.private ? (
        <p className={css.note}>In a private session of {name}'s: its words are hers.</p>
      ) : (
        <>
          <p className={css.words}>{b.line}</p>
          {b.summary && <p className={css.note}>{b.summary}</p>}
        </>
      )}
      {b.tags.length > 0 && <p className={css.meta}>{b.tags.map((t) => `#${t}`).join(' ')}</p>}
      <div className={css.buttons}>
        <button type="button" className={css.secondary} onClick={() => push(`memory/${b.number}`)}>
          Open
        </button>
        {!b.private && <MomentLink b={b} />}
        <PinButton b={b} />
      </div>
    </div>
  );
}

/** The moment itself, in the conversation at its turn: linked, not shown (the witness's call). */
function MomentLink({ b }: { b: Bookmark }) {
  return (
    <a className={css.secondary} style={{ display: 'inline-flex', alignItems: 'center', textDecoration: 'none' }} href={formatHash({ tab: 'chat', path: `turn/${b.session_key}/${b.anchor_ref}` })}>
      Open the moment ›
    </a>
  );
}

/** Pin or Unpin: the witness's decision, recorded with who made it; the route takes no note. */
function PinButton({ b }: { b: Bookmark }) {
  const { id } = useSubject();
  const queries = useQueryClient();
  const pinned = b.pinned_at !== null;
  const act = useMutation({
    mutationFn: () => (pinned ? api.unpin(id, b.number) : api.pin(id, b.number)),
    onSuccess: () => queries.invalidateQueries({ queryKey: ['resident', id, 'memory'] }),
  });
  return (
    <>
      <button type="button" className={css.small} disabled={act.isPending} onClick={() => act.mutate()}>
        {pinned ? 'Unpin' : 'Pin'}
      </button>
      {act.error && <p className={css.note}>That didn't go through: {(act.error as Error).message}</p>}
    </>
  );
}

/**
 * One bookmark (`memory/<n>`), from `GET /bookmarks/:n`. The moment is
 * linked, not shown (the witness's call); a bookmark from a private
 * session she hasn't shared arrives marked, its words withheld
 * (kumbukumbu#62), and is said to be hers.
 */
export function BookmarkPage({ number, onBack }: { number: number; onBack: () => void }) {
  const { id, name } = useSubject();
  const one = useQuery({
    queryKey: ['resident', id, 'memory', 'bookmark', number],
    queryFn: () => api.bookmarkDetail(id, number).then(({ bookmark }) => bookmark),
  });
  const index = useQuery({ queryKey: ['resident', id, 'memory', 'index'], queryFn: () => api.indexNow(id) });
  const b = one.data;
  return (
    <ScrollArea label={`Bookmark ${number}`}>
      <div className={css.page}>
        <PageHead title={`Bookmark ${number}`} onBack={onBack} />
        {one.isPending && <p className={css.note}>Reading…</p>}
        {one.error && <p className={css.note}>This bookmark couldn't be read here.</p>}
        {b && (
          <div className={b.pinned_at ? css.cardHers : css.card}>
            {b.private ? (
              <p className={css.note}>Made in a private session of {name}'s that she hasn't shared: its words, and the moment around it, are hers.</p>
            ) : (
              <>
                <p className={css.words}>{b.line}</p>
                {b.summary && <p className={css.plain}>{b.summary}</p>}
              </>
            )}
            <p className={css.meta}>
              {new Date(b.anchor_at).toLocaleString()} · {spanWords(b.turns_back).toUpperCase()} · BOOKMARKED BY {who(b.added_by.kind, name).toUpperCase()}
              {b.proposed_by ? ' · PROPOSED BY YOU' : ''}
            </p>
            {b.pinned_at && (
              <p className={css.meta}>
                PINNED BY {who(b.pinned_by?.kind, name).toUpperCase()} {day(b.pinned_at)}
                {index.data?.listed.includes(b.number) ? ' · IN FRONT OF EVERY TURN' : ''}
              </p>
            )}
            {b.last_indexed_at && <p className={css.meta}>LAST LISTED IN A TURN {day(b.last_indexed_at)}</p>}
            {b.tags.length > 0 && <p className={css.meta}>{b.tags.map((t) => `#${t}`).join(' ')}</p>}
            <div className={css.buttons}>
              {!b.private && <MomentLink b={b} />}
              <PinButton b={b} />
            </div>
          </div>
        )}
      </div>
    </ScrollArea>
  );
}

// How retrieval has used each target (the resident's work order,
// 2026-11-02): considered by the memory agent, returned to the brain,
// used by it. The same numbers she reads with memory_use.
function Use({ name, rows }: { name: string; rows: RetrievalCount[] }) {
  return (
    <section className={css.section} aria-label="How retrieval was used">
      <p className={css.note}>
        Considered: the memory agent ranked it. Returned: it was put in front of {name}. Used: {name} opened, read or cited it. {name} reads the
        same numbers; nothing is reweighted from them until you have both looked.
      </p>
      {rows.length === 0 && <p className={css.note}>Nothing is counted yet.</p>}
      {rows.map((r) => (
        <div key={r.target} className={css.card}>
          <span className={mcss.target}>{r.target}</span>
          <span className={css.meta}>
            {r.considered} CONSIDERED · {r.returned} RETURNED · {r.used} USED · LAST USED {r.last_used_at ? day(r.last_used_at) : 'NEVER'}
          </span>
        </div>
      ))}
    </section>
  );
}
