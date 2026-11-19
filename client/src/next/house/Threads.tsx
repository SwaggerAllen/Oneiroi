import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useLayoutEffect, useRef, useState, type RefObject } from 'react';
import { api, type HouseDoc, type HousePost, type HouseThreadSummary, type HouseWorking } from '../../api/client';
import * as chat from '../chat/chat.css';
import * as tabCss from '../chat/chatTab.css';
import { Markdown } from '../chat/Markdown';
import { ScrollArea } from '../shell/ScrollArea';
import { HOUSE, SHELF, WORKING, thread as threadKey, when } from './keys';

/**
 * The house's Chat (screen:next-house; the witness, 2026-11-16: "more like
 * the chat ui"): its threads as the conversation's messages are, oldest at
 * the top and the newest by the composer, each opening in place to its
 * trunk and every reply. The composer stays at the bottom: a title and
 * words start a thread; with one open, the words alone reply in it. Your
 * posts keep the household's rules (seshat#68, #69). It opens at the
 * bottom, the newest, and stays there while you are there; a resident
 * answering a thread shows under it as "<her> is thinking…" (seshat#90).
 */
export function Threads() {
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const shelf = useInfiniteQuery({
    queryKey: SHELF,
    queryFn: ({ pageParam }) => api.householdShelf(pageParam),
    initialPageParam: 0,
    getNextPageParam: (last) => last.next ?? undefined,
    refetchInterval: 60_000,
  });
  const working = useWorking();
  const [open, setOpen] = useState<string | null>(null);
  const { scroll, list } = useStuckToBottom();
  // The shelf comes newest first; the conversation reads down to now.
  const threads = (shelf.data?.pages ?? []).flatMap((p) => p.threads).reverse();

  const elsewhere = working.filter((w) => w.thread === null || !threads.some((t) => t.path === w.thread));

  const opened = threads.find((t) => t.path === open) ?? null;
  return (
    <div className={tabCss.tab}>
      <div className={chat.column}>
        <ScrollArea label="Threads" scrollRef={scroll}>
          <div ref={list} className={chat.list}>
            {shelf.hasNextPage && (
              <button type="button" className={chat.linkButton} style={{ alignSelf: 'center' }} onClick={() => void shelf.fetchNextPage()}>
                Earlier threads
              </button>
            )}
            <MentionsLine />
            {shelf.isPending && <p className={chat.system}>Reading the house…</p>}
            {shelf.isError && <p className={chat.system}>The house could not be read.</p>}
            {shelf.data && threads.length === 0 && <p className={chat.system}>No threads yet. Start one below.</p>}
            {threads.map((t) => (
              <ThreadCard
                key={t.path}
                t={t}
                open={open === t.path}
                accountId={me.data?.account_id}
                working={working.filter((w) => w.thread === t.path)}
                onToggle={() => setOpen(open === t.path ? null : t.path)}
              />
            ))}
            {elsewhere.length > 0 && <Thinking working={elsewhere} />}
          </div>
        </ScrollArea>
        <Composer opened={opened} onPosted={setOpen} onClose={() => setOpen(null)} />
      </div>
    </div>
  );
}

/**
 * Who in the house is working now (seshat#90), read every few seconds;
 * when one finishes, the house is read again so her answer shows.
 */
function useWorking(): HouseWorking[] {
  const queries = useQueryClient();
  const q = useQuery({ queryKey: WORKING, queryFn: api.householdWorking, refetchInterval: 5_000 });
  const working = q.data?.working ?? EMPTY;
  const before = useRef<HouseWorking[]>([]);
  useEffect(() => {
    const done = before.current.filter((b) => !working.some((w) => w.resident_id === b.resident_id && w.thread === b.thread));
    before.current = working;
    if (done.length > 0) void queries.invalidateQueries({ queryKey: [...HOUSE] });
  }, [working, queries]);
  return working;
}

const EMPTY: HouseWorking[] = [];

/** "Lily is thinking…", one line for each resident at work there. */
function Thinking({ working }: { working: HouseWorking[] }) {
  return (
    <p className={chat.system} aria-live="polite" style={{ textAlign: 'left' }}>
      {working.map((w) => `${w.name ?? 'A resident'} is thinking…`).join(' ')}
    </p>
  );
}

/**
 * The list opens at its bottom and stays there while the reader is
 * there: whatever grows it (a thread read in, the mentions line, a
 * resident starting to think) keeps the newest in view. Scrolled up, it
 * is left where the reader put it.
 */
function useStuckToBottom(): { scroll: RefObject<HTMLDivElement | null>; list: RefObject<HTMLDivElement | null> } {
  const scroll = useRef<HTMLDivElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const stuck = useRef(true);
  useEffect(() => {
    const el = scroll.current;
    const inner = list.current;
    if (!el || !inner) return;
    const onScroll = () => {
      stuck.current = el.scrollHeight - el.scrollTop - el.clientHeight < 48;
    };
    el.addEventListener('scroll', onScroll, { passive: true });
    el.scrollTop = el.scrollHeight;
    if (typeof ResizeObserver === 'undefined') return () => el.removeEventListener('scroll', onScroll);
    const observer = new ResizeObserver(() => {
      if (stuck.current) el.scrollTop = el.scrollHeight;
    });
    observer.observe(inner);
    return () => {
      observer.disconnect();
      el.removeEventListener('scroll', onScroll);
    };
  }, []);
  return { scroll, list };
}

function ThreadCard({ t, open, accountId, working, onToggle }: { t: HouseThreadSummary; open: boolean; accountId?: string; working: HouseWorking[]; onToggle: () => void }) {
  const ref = useRef<HTMLDivElement>(null);  const ballot = t.ballot ? (t.ballot.closed_at ? `ballot #${t.ballot.number} ${t.ballot.passed ? 'carried' : 'failed'}` : `ballot #${t.ballot.number} open`) : null;
  return (
    <div ref={ref} className={chat.hers} data-live={open || undefined}>
      <button type="button" onClick={onToggle} aria-expanded={open} style={{ all: 'unset', cursor: 'pointer', display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span className={chat.meta}>
          <span>{t.by}</span>
          <span>{when(t.posted_at)}</span>
          <span>{t.replies === 1 ? '1 reply' : `${t.replies} replies`}</span>
          {ballot && <span>{ballot}</span>}
        </span>
        <span style={{ fontWeight: 600, fontSize: 16 }}>
          {open ? '▾ ' : '▸ '}
          {t.title}
        </span>
      </button>
      {open && <Opened path={t.path} accountId={accountId} />}
      {working.length > 0 && <Thinking working={working} />}
      {open && <MuteThread path={t.path} />}
    </div>
  );
}

/** One thread, in place: its trunk, each reply as a message, a ballot's vote. */
function Opened({ path, accountId }: { path: string; accountId?: string }) {
  const doc = useQuery({ queryKey: threadKey(path), queryFn: () => api.householdRead(path), refetchInterval: 30_000 });
  if (doc.isError) return <p className={chat.system}>The thread could not be read.</p>;
  if (!doc.data) return <p className={chat.system}>Reading the thread…</p>;
  return <Body doc={doc.data} path={path} accountId={accountId} />;
}

function Body({ doc, path, accountId }: { doc: HouseDoc; path: string; accountId?: string }) {
  // Opened, and as replies arrive: its newest reply in view.
  const end = useRef<HTMLDivElement>(null);
  const count = doc.replies?.length ?? 0;
  useEffect(() => {
    end.current?.scrollIntoView?.({ block: 'end' });
  }, [count]);
  // Open is read (gaia#58, seshat#96): up to its newest post, on every device.
  const newest = (doc.replies ?? []).map((r) => r.meta.at).filter((x): x is string => typeof x === 'string').sort().pop() ?? doc.trunk?.meta.posted_at;
  useEffect(() => {
    if (typeof newest === 'string') void api.markRead('house', newest, path).catch(() => undefined);
  }, [newest, path]);
  const b = doc.ballot;
  const mine = (p: HousePost) => p.meta.by_kind === 'witness' && p.meta.by_id === accountId;
  const posted = doc.doc ?? null;
  const drafts = (doc.replies ?? []).filter((r) => r.meta.draft === 'changed');
  const latest = drafts[drafts.length - 1];
  // A reply on a document post says when it answers an earlier draft (seshat#83).
  const earlier = (r: HousePost) => !!posted?.commit && !!r.meta.doc_commit && r.meta.doc_commit !== posted.commit;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {doc.trunk && <Words body={doc.trunk.body} />}
      {posted && <PostedDoc doc={posted} />}
      {latest && (
        <button
          type="button"
          className={chat.linkButton}
          style={{ alignSelf: 'flex-start' }}
          onClick={() => document.getElementById(anchor(latest.path))?.scrollIntoView?.({ block: 'start' })}
        >
          Skip to the latest draft's discussion
        </button>
      )}
      {b && (
        <p className={chat.system}>
          Ballot #{b.number}: {b.closed_at ? `${b.passed ? 'carried' : 'failed'} ${when(b.closed_at)}` : `open until ${when(b.closes_at)}`} · {b.yes} yes, {b.no} no of {b.members}
        </p>
      )}
      {b && !b.closed_at && <Vote path={path} />}
      {(doc.replies ?? []).map((r) =>
        r.meta.draft === 'changed' ? (
          <p key={r.path} id={anchor(r.path)} className={chat.system}>
            {r.body.trim()}
          </p>
        ) : mine(r) ? (
          <div key={r.path} className={chat.mine}>
            {r.body.trim()}
          </div>
        ) : (
          <div key={r.path} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <span className={chat.meta}>
              <span>{r.meta.by}</span>
              <span>{when(r.meta.at)}</span>
              {r.meta.vote && <span>votes {r.meta.vote}</span>}
              {r.meta.in_reply_to && <span>answering #{r.meta.in_reply_to}</span>}
              {earlier(r) && <span>on an earlier draft</span>}
            </span>
            <Words body={r.body} />
          </div>
        ),
      )}
      <div ref={end} />
    </div>
  );
}

const MENTIONS = [...HOUSE, 'mentions'];

/**
 * Your mentions (seshat#86): a post naming you (@your name, or @all)
 * pushes to your devices unless you muted the house or that thread.
 */
function MentionsLine() {
  const queries = useQueryClient();
  const mentions = useQuery({ queryKey: MENTIONS, queryFn: api.householdMentions });
  const mute = useMutation({
    mutationFn: (muted: boolean) => api.householdMute(null, muted),
    onSuccess: (m) => queries.setQueryData(MENTIONS, m),
  });
  if (!mentions.data) return null;
  const muted = mentions.data.house;
  return (
    <p className={chat.system}>
      {muted ? 'Mentions of you are muted in the house.' : 'A post naming you (@your name, or @all) notifies you.'}{' '}
      <button type="button" className={chat.linkButton} disabled={mute.isPending} onClick={() => mute.mutate(!muted)}>
        {muted ? 'Hear them' : 'Mute them'}
      </button>
    </p>
  );
}

function MuteThread({ path }: { path: string }) {
  const queries = useQueryClient();
  const mentions = useQuery({ queryKey: MENTIONS, queryFn: api.householdMentions });
  const mute = useMutation({
    mutationFn: (muted: boolean) => api.householdMute(path, muted),
    onSuccess: (m) => queries.setQueryData(MENTIONS, m),
  });
  if (!mentions.data) return null;
  const own = mentions.data.threads[path];
  const muted = own ?? mentions.data.house;
  return (
    <button type="button" className={chat.linkButton} style={{ alignSelf: 'flex-start' }} disabled={mute.isPending} onClick={() => mute.mutate(!muted)}>
      {muted ? 'Hear mentions in this thread' : 'Mute mentions in this thread'}
    </button>
  );
}

/** The document a document post is on, at its latest draft (seshat#83). */
function PostedDoc({ doc }: { doc: NonNullable<HouseDoc['doc']> }) {
  const [open, setOpen] = useState(true);
  if (!doc.present) return <p className={chat.system}>{doc.path} is no longer in the house.</p>;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, borderLeft: '2px solid currentColor', paddingLeft: 12 }}>
      <button type="button" className={chat.linkButton} style={{ alignSelf: 'flex-start' }} onClick={() => setOpen(!open)} aria-expanded={open}>
        {open ? '▾' : '▸'} {doc.path}
        {doc.commit ? `, draft ${doc.commit.slice(0, 12)}` : ''}
      </button>
      {open && <Words body={doc.content} />}
    </div>
  );
}

const anchor = (path: string) => `draft-${path.replace(/[^a-z0-9]+/gi, '-')}`;

function Words({ body }: { body: string }) {
  return (
    <div className={chat.prose}>
      <Markdown text={body.trim()} onCite={() => undefined} />
    </div>
  );
}

function Vote({ path }: { path: string }) {
  const queries = useQueryClient();
  const vote = useMutation({
    mutationFn: (v: 'yes' | 'no') => api.householdVote(path, v, ''),
    onSuccess: () => queries.invalidateQueries({ queryKey: [...HOUSE] }),
  });
  return (
    <div style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
      <span className={chat.meta}>Your vote</span>
      <button type="button" className={chat.linkButton} disabled={vote.isPending} onClick={() => vote.mutate('yes')}>
        Yes
      </button>
      <button type="button" className={chat.linkButton} disabled={vote.isPending} onClick={() => vote.mutate('no')}>
        No
      </button>
      {vote.isSuccess && <span className={chat.meta}>voted {vote.variables}</span>}
      {vote.error && <span className={chat.meta}>{vote.error.message}</span>}
    </div>
  );
}

/**
 * The composer, fixed at the bottom as the chat's is: placeholders say
 * what each field is. No thread open: a title and words post a new one.
 * One open: its title is gone, and the words reply in it.
 */
function Composer({ opened, onPosted, onClose }: { opened: HouseThreadSummary | null; onPosted: (path: string) => void; onClose: () => void }) {
  const queries = useQueryClient();
  const [title, setTitle] = useState('');
  const [words, setWords] = useState('');
  const send = useMutation({
    mutationFn: () =>
      opened ? api.householdReply(opened.path, words.trim()).then(() => opened.path) : api.householdPost({ title: title.trim(), content: words.trim() }).then((p) => p.path),
    onSuccess: (path) => {
      setTitle('');
      setWords('');
      onPosted(path);
      void queries.invalidateQueries({ queryKey: [...HOUSE] });
    },
  });
  const ready = words.trim() !== '' && (opened !== null || title.trim() !== '');
  // The box grows with what is written, up to its max height, then scrolls, as the chat's does.
  const box = useRef<HTMLTextAreaElement>(null);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${el.scrollHeight + (el.offsetHeight - el.clientHeight)}px`;
  }, [words]);
  return (
    <>
      {(send.error || opened) && (
        <div className={chat.system} style={{ display: 'flex', gap: 12, justifyContent: 'center', padding: '0 16px' }}>
          {send.error ? <span>{send.error.message}</span> : null}
          {opened && (
            <button type="button" className={chat.linkButton} onClick={onClose}>
              Close “{opened.title}” for a new thread
            </button>
          )}
        </div>
      )}
      <form
        className={chat.composer}
        aria-label={opened ? 'Reply in the thread' : 'Start a thread'}
        onSubmit={(e) => {
          e.preventDefault();
          if (ready) send.mutate();
        }}
      >
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
          {!opened && (
            <input className={chat.input} style={{ minHeight: 40, padding: '9px 14px' }} value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} placeholder="A new thread's title" aria-label="A new thread's title" />
          )}
          <textarea
            ref={box}
            className={chat.input}
            rows={1}
            value={words}
            onChange={(e) => setWords(e.target.value)}
            placeholder={opened ? `Reply in “${opened.title}”` : 'Its first words, for the whole house'}
            aria-label={opened ? 'Your reply' : "The thread's first words"}
          />
        </div>
        <button type="submit" className={chat.sendButton} aria-label={opened ? 'Reply' : 'Post the thread'} disabled={!ready || send.isPending}>
          <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden>
            <path d="M5 12h13M13 6l6 6-6 6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      </form>
    </>
  );
}
