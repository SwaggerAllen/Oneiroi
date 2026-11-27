import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { api, RequestFailed, type HouseDoc } from '../../api/client';
import type { DocumentContext, QueueOverview, ResidentThread } from '../../api/types';
import { Markdown } from '../chat/Markdown';
import { DOC_CONTEXT } from '../live/notices';
import * as css from '../settings/settings.css';
import { HOUSE, thread as houseThreadKey, when } from './keys';
import { actName, pinOf, placeOf, postKind, roleChoices, unpinned, withMd, type Place } from './queueText';
import * as w from './work.css';
import { useHouseLive, useWorkNav, workPath } from './workRoutes';

const QUEUE = [...HOUSE, 'queue'];

/** What the document screen knows around a document (its threads, tasks, the review open for you); read again live. */
function useDocContext(citation: string | null) {
  return useQuery({
    queryKey: [...DOC_CONTEXT, citation ? unpinned(citation) : ''],
    queryFn: () => api.documentContext(citation as string),
    enabled: !!citation,
    retry: false,
  });
}

/** The house queue's overview, for the task picker and the house's channel; nothing when the caller is in no house. */
function useOverview() {
  return useQuery({ queryKey: QUEUE, queryFn: api.queue, retry: false });
}

/**
 * The one document screen (design/document-threads.md §5, the queue
 * mocks' Review, Record and RecordLoose): reached from Records, from a
 * task's documents and from a review. The document in the voice's serif,
 * its citation at its pin, the task it is part of (or Start a task / Add
 * to task), and a floating bar: its one thread, and a review of it open
 * for you.
 */
export function DocumentScreen({ citation, onBack }: { citation: string; onBack: () => void }) {
  const place = placeOf(citation);
  const context = useDocContext(citation);
  const residentId = context.data?.resident_id ?? null;
  // The same reads, under the same keys, as Records' own views of it.
  const house = useQuery({
    queryKey: houseThreadKey(place?.path ?? ''),
    queryFn: () => api.householdRead(place?.path ?? ''),
    enabled: !!place?.house,
    retry: (n, e) => n < 2 && !(e instanceof RequestFailed && e.status === 404),
  });
  const hers = useQuery({
    queryKey: ['resident', residentId, 'records', 'doc', withMd(place?.path ?? ''), 'full'],
    queryFn: () => api.documentRead(residentId as string, withMd(place?.path ?? '')),
    enabled: !!place && !place.house && !!residentId,
    retry: (n, e) => n < 2 && !(e instanceof RequestFailed && e.status === 404),
  });
  const read = place?.house ? house : hers;
  const words = place?.house ? house.data && { title: house.data.title, content: house.data.content } : hers.data && { title: hers.data.document.title, content: hers.data.content };
  const pin = pinOf(citation);
  const title = words?.title ?? place?.path.split('/').pop()?.replace(/\.md$/, '') ?? citation;
  return (
    <div className={w.docScreen}>
      <button type="button" className={css.back} onClick={onBack}>
        ‹ Back
      </button>
      <div className={w.citation}>
        {unpinned(citation)}
        {pin ? ` @${pin.slice(0, 7)}` : ''}
      </div>
      <DocumentTasks citation={citation} />
      <h1 className={w.pageTitle}>{title}</h1>
      {!place && <p className={css.refused}>This is not a document citation.</p>}
      {(read.isPending && read.fetchStatus !== 'idle') || context.isPending ? <p className={css.note}>Reading…</p> : null}
      {(read.isError || context.isError) && <p className={css.refused}>This document could not be read.</p>}
      {words && (
        <div className={w.body}>
          <Markdown text={strip(words.content)} onCite={() => undefined} />
        </div>
      )}
      <ThreadBar citation={citation} />
    </div>
  );
}

/** A document's front matter is the record's bookkeeping, not its words. */
const strip = (text: string) => (text.startsWith('---\n') ? text.replace(/^---\n[\s\S]*?\n---\n?/, '') : text);

/**
 * The task line under a document's citation: "Part of task #9 · title ›"
 * for each task it belongs to; when it belongs to none, Start a task from
 * this, and Add to task (sunna#91).
 */
export function DocumentTasks({ citation }: { citation: string }) {
  const context = useDocContext(citation);
  const nav = useWorkNav();
  const [adding, setAdding] = useState(false);
  if (!context.data) return null;
  const tasks = context.data.tasks;
  if (tasks.length > 0)
    return (
      <div className={w.chips}>
        {tasks.map((t) => (
          <button key={t.number} type="button" className={w.taskLink} onClick={() => nav(workPath.task(t.number))}>
            Part of task #{t.number} · {t.title}
            {t.status !== 'open' ? ` (${t.status})` : ''} ›
          </button>
        ))}
      </div>
    );
  return (
    <>
      <div className={css.row}>
        <button type="button" className={css.secondary} onClick={() => nav(workPath.newTask(unpinned(citation)))}>
          + Start a task from this
        </button>
        <button type="button" className={css.secondary} aria-expanded={adding} onClick={() => setAdding(!adding)}>
          Add to task {adding ? '▴' : '▾'}
        </button>
      </div>
      {adding && <AddToTask citation={unpinned(citation)} onDone={() => setAdding(false)} />}
    </>
  );
}

/**
 * Add to task: search the open tasks, choose one and the role the
 * document takes there. An empty slot is filled (its activities work on
 * it); anything else is attached as a source (sunna#91).
 */
export function AddToTask({ citation, onDone }: { citation: string; onDone: () => void }) {
  const overview = useOverview();
  const queries = useQueryClient();
  const [q, setQ] = useState('');
  const [chosen, setChosen] = useState<number | null>(null);
  const [role, setRole] = useState('');
  const add = useMutation({
    mutationFn: ({ task, role, fills }: { task: number; role: string; fills: boolean }) => (fills ? api.queueFillSlot(task, role, citation) : api.queueAttachDocument(task, citation, role)),
    onSuccess: () => {
      void queries.invalidateQueries({ queryKey: QUEUE });
      onDone();
    },
  });
  if (overview.isError) return <p className={css.note}>The house queue could not be read: are you in a household?</p>;
  if (!overview.data) return <p className={css.note}>Reading the house queue…</p>;
  const open = overview.data.tasks.filter((t) => t.status === 'open');
  const words = q.trim().toLowerCase();
  const shown = open.filter((t) => !words || `#${t.number} ${t.title} ${t.project}`.toLowerCase().includes(words));
  const task = open.find((t) => t.number === chosen) ?? null;
  const choices = task ? roleChoices(task.documents ?? []) : [];
  const picked = choices.find((c) => c.role === role) ?? choices[0];
  return (
    <div className={w.picker} role="group" aria-label="Add to task">
      <input className={css.input} placeholder="Search the open tasks" aria-label="Search the open tasks" value={q} onChange={(e) => setQ(e.target.value)} />
      {shown.length === 0 && <p className={css.note}>No open task matches.</p>}
      {shown.slice(0, 8).map((t) => (
        <button key={t.number} type="button" className={w.pickRow} aria-pressed={chosen === t.number} onClick={() => (setChosen(t.number), setRole(''))}>
          <span>
            #{t.number} · {t.title}
          </span>
          <span className={w.meta}>
            {t.project}
            {t.template ? ` · ${t.template}` : ''}
          </span>
        </button>
      ))}
      {task && picked && (
        <>
          <label className={css.field}>
            <span>As its</span>
            <select className={css.input} value={picked.role} onChange={(e) => setRole(e.target.value)}>
              {choices.map((c) => (
                <option key={c.role} value={c.role}>
                  {c.label}
                </option>
              ))}
            </select>
          </label>
          {picked.fills && <p className={css.note}>{picked.role} is empty on #{task.number}, so its activities can work on this.</p>}
          <div className={css.row}>
            <button type="button" className={css.primary} disabled={add.isPending} onClick={() => add.mutate({ task: task.number, role: picked.role, fills: picked.fills })}>
              Add to #{task.number}
            </button>
            <button type="button" className={css.quiet} onClick={onDone}>
              Cancel
            </button>
          </div>
        </>
      )}
      {add.error && <p className={css.refused}>{(add.error as Error).message}</p>}
    </div>
  );
}

type Space = 'mine' | 'house';

/** One post of either thread, as the sheet and the bar read it. */
interface Post {
  key: string;
  by: string;
  at: string;
  body: string;
  meta: Record<string, string>;
}

function postsOfMine(t: ResidentThread | undefined): Post[] {
  if (!t) return [];
  return [...(t.trunk ? [t.trunk] : []), ...t.replies].map((p, i) => ({ key: `${i}`, by: p.meta.by ?? '', at: p.meta.at ?? p.meta.posted_at ?? '', body: p.body, meta: p.meta }));
}

function postsOfHouse(d: HouseDoc | undefined): Post[] {
  if (!d) return [];
  return [...(d.trunk ? [{ ...d.trunk, path: 'trunk' }] : []), ...(d.replies ?? [])].map((p) => ({ key: p.path, by: p.meta.by ?? '', at: p.meta.at ?? p.meta.posted_at ?? '', body: p.body, meta: p.meta }));
}

/** The threads a document has, each read whole while the screen is up; live through the channels, never polled. */
function useThreads(citation: string) {
  const context = useDocContext(citation);
  const c = context.data;
  const residentId = c?.resident_id ?? null;
  const minePath = c?.mine?.path ?? null;
  const housePath = c?.house?.path ?? null;
  const mine = useQuery({
    queryKey: ['resident', residentId, 'threads', minePath],
    queryFn: () => api.residentThread(residentId as string, minePath as string),
    enabled: !!residentId && !!minePath,
  });
  const house = useQuery({ queryKey: houseThreadKey(housePath ?? ''), queryFn: () => api.householdRead(housePath as string), enabled: !!housePath });
  return { context: c, mine: postsOfMine(mine.data), house: postsOfHouse(house.data) };
}

/**
 * The floating bar at the document's foot: its thread (how many posts,
 * the last of them; it opens the thread) and, when a review of this
 * document is open for you, the review's controls (seshat#110: the
 * decision posts into the thread).
 */
export function ThreadBar({ citation }: { citation: string }) {
  const overview = useOverview();
  useHouseLive(overview.data?.household_id);
  const { context, mine, house } = useThreads(citation);
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const [open, setOpen] = useState(false);
  if (!context) return null;
  const place = placeOf(citation);
  // Hers first: the dyad's thread is the one her chat carries; the house's when it is the house's document.
  const posts = place?.house ? house : mine.length > 0 || !context.house ? mine : house;
  const last = posts[posts.length - 1];
  const both = !!context.house && !place?.house;
  return (
    <div className={w.floatBar}>
      <button type="button" className={w.threadRow} onClick={() => setOpen(true)} aria-label="Open the thread">
        <span className={w.threadCount}>Thread · {posts.length}</span>
        <span className={w.threadLast}>{last ? `${postKind(last.meta, me.data?.account_id) === 'mine' ? 'you' : last.by || 'someone'}: ${last.body.trim().split('\n')[0]}` : place?.house ? 'No thread yet · Start one' : 'No thread yet · Start one with her'}</span>
        {both && <span className={w.meta}>also in the house</span>}
        <span aria-hidden>›</span>
      </button>
      {context.review && <ReviewControls context={context} overview={overview.data} />}
      {open && <ThreadSheet citation={citation} onClose={() => setOpen(false)} />}
    </div>
  );
}

/**
 * A review of this document open for you (the existing decide route):
 * a note, then Approve, Ask for changes or Decline. A refusal goes back
 * to the template's throwback.
 */
function ReviewControls({ context, overview }: { context: DocumentContext; overview?: QueueOverview }) {
  const r = context.review!;
  const queries = useQueryClient();
  const [note, setNote] = useState('');
  const decide = useMutation({
    // An approval names the revision it approved, its pin (sunna#110): the one this screen shows.
    mutationFn: (outcome: 'approved' | 'changes' | 'declined') => api.queueMove(r.task, r.act, 'decide', { outcome, note, pin: context.revision ?? undefined }),
    onSuccess: () => {
      setNote('');
      void queries.invalidateQueries({ queryKey: HOUSE });
      void queries.invalidateQueries({ queryKey: ['resident'] });
    },
  });
  const task = overview?.tasks.find((t) => t.number === r.task);
  const [open, setOpen] = useState(false);
  const line = (
    <span className={w.reviewLine}>
      {actName(r)} is yours · {r.view}
      {task ? ` · task #${task.number}` : ''}
    </span>
  );
  if (!open)
    return (
      <div className={w.top}>
        {line}
        <button type="button" className={css.primary} onClick={() => setOpen(true)}>
          Review
        </button>
      </div>
    );
  return (
    <div className={css.column}>
      {line}
      {r.action && (
        <span className={w.meta}>
          Approving lets {r.action}
          {r.destination ? ` to ${r.destination}` : ''} happen for this revision; a refusal sends it back{r.throwback ? ` to ${r.throwback}` : ''}.
        </span>
      )}
      <span className={w.meta}>
        {context.revision
          ? `Reviewing the revision at ${context.revision.slice(0, 7)}: an approval names it.`
          : r.artifact
            ? 'The revision shown here could not be read, so it cannot be approved from this screen; ask for changes or decline, or try again.'
            : null}
      </span>
      <textarea className={w.replyBox} rows={2} placeholder="Your note (it posts to the thread)" aria-label="Your note" value={note} onChange={(e) => setNote(e.target.value)} />
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={decide.isPending || !note.trim() || (!!r.artifact && !context.revision)} onClick={() => decide.mutate('approved')}>
          Approve
        </button>
        <button type="button" className={css.secondary} disabled={decide.isPending || !note.trim()} onClick={() => decide.mutate('changes')}>
          Ask for changes
        </button>
        <button type="button" className={css.quiet} disabled={decide.isPending || !note.trim()} onClick={() => decide.mutate('declined')}>
          Decline
        </button>
      </div>
      {decide.error && <p className={css.refused}>{(decide.error as Error).message}</p>}
    </div>
  );
}

/**
 * The document's one thread (seshat#107, #109): a resident's document
 * has hers, Between you two; once it is shared to the house, its house
 * thread too, In the house. Messages as bubbles: yours, theirs, and the
 * platform's lines (a review's decision) apart. A reply posts at once and
 * shows as the channel says it was written.
 */
export function ThreadSheet({ citation, onClose }: { citation: string; onClose: () => void }) {
  const { context, mine, house } = useThreads(citation);
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const place = placeOf(citation);
  const spaces: Space[] = place?.house ? ['house'] : context?.house ? ['mine', 'house'] : ['mine'];
  const [space, setSpace] = useState<Space>(spaces[0]);
  const posts = space === 'house' ? house : mine;
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => {
    end.current?.scrollIntoView?.({ block: 'end' });
  }, [posts.length, space]);
  useEffect(() => {
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', esc);
    return () => window.removeEventListener('keydown', esc);
  }, [onClose]);
  const title = (space === 'house' ? context?.house?.title : context?.mine?.title) ?? place?.path ?? citation;
  // Over everything, the tab bar too: the sheet is the page while it is open.
  return createPortal(
    <div className={w.scrim} onClick={onClose}>
      <div className={w.sheet} role="dialog" aria-modal="true" aria-label="The document's thread" onClick={(e) => e.stopPropagation()}>
        <div className={w.sheetHead}>
          <div className={w.sheetTop}>
            <h2 className={w.sheetTitle}>Thread · {title}</h2>
            <button type="button" className={css.quiet} onClick={onClose}>
              Close ✕
            </button>
          </div>
          {spaces.length > 1 && (
            <div className={w.segmented} role="group" aria-label="Which thread">
              <button type="button" className={w.segment} aria-pressed={space === 'mine'} onClick={() => setSpace('mine')}>
                Between you two
              </button>
              <button type="button" className={w.segment} aria-pressed={space === 'house'} onClick={() => setSpace('house')}>
                In the house
              </button>
            </div>
          )}
          <span className={w.meta}>{space === 'house' ? 'One thread per document: its post in the house; reviews post here.' : 'One thread per document: hers and yours, beside the document in her chat; reviews post here.'}</span>
        </div>
        <div className={w.messages}>
          {posts.length === 0 && <p className={css.note}>No thread yet. What you write starts it.</p>}
          {posts.map((p) => {
            const kind = postKind(p.meta, me.data?.account_id);
            if (kind === 'platform')
              return (
                <div key={p.key} className={w.platform}>
                  {p.body.trim()}
                  <div className={w.byline}>{when(p.at)}</div>
                </div>
              );
            return (
              <div key={p.key} style={{ display: 'flex', flexDirection: 'column', alignItems: kind === 'mine' ? 'flex-end' : 'flex-start' }}>
                <div className={kind === 'mine' ? w.bubbleMine : w.bubbleHers}>{p.body.trim()}</div>
                <span className={w.byline}>
                  {kind === 'mine' ? 'you' : p.by} · {when(p.at)}
                </span>
              </div>
            );
          })}
          <div ref={end} />
        </div>
        <Reply citation={citation} place={place} context={context} space={space} />
      </div>
    </div>,
    document.body,
  );
}

function Reply({ citation, place, context, space }: { citation: string; place: Place | null; context?: DocumentContext; space: Space }) {
  const queries = useQueryClient();
  const [words, setWords] = useState('');
  const send = useMutation({
    mutationFn: async () => {
      const content = words.trim();
      if (space === 'house') {
        if (context?.house) return api.householdReply(context.house.path, content);
        // A post with doc on a house document starts its one thread, or answers it.
        if (place?.house) return api.householdPost({ doc: place.path, content });
        throw new Error('Her document has no thread in the house until it is shared there.');
      }
      const rid = context?.resident_id;
      if (!rid || !place) throw new Error('Whose document this is could not be read.');
      if (context?.mine) return api.residentThreadReply(rid, context.mine.path, content);
      return api.residentThreadPost(rid, { doc: withMd(place.path), content });
    },
    onSuccess: () => {
      setWords('');
      void queries.invalidateQueries({ queryKey: DOC_CONTEXT });
      void queries.invalidateQueries({ queryKey: [...HOUSE, 'thread'] });
      if (context?.resident_id) void queries.invalidateQueries({ queryKey: ['resident', context.resident_id, 'threads'] });
    },
  });
  return (
    <>
      {send.error && <p className={css.refused} style={{ margin: '0 16px' }}>{(send.error as Error).message}</p>}
      <form
        className={w.reply}
        aria-label="Reply in the thread"
        onSubmit={(e) => {
          e.preventDefault();
          if (words.trim()) send.mutate();
        }}
      >
        <textarea className={w.replyBox} rows={2} value={words} onChange={(e) => setWords(e.target.value)} placeholder="Reply in the thread" aria-label="Your reply" data-citation={citation} />
        <button type="submit" className={css.primary} disabled={!words.trim() || send.isPending}>
          Send
        </button>
      </form>
    </>
  );
}
