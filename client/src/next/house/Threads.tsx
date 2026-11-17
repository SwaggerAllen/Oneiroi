import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { api, type HouseDoc, type HousePost, type HouseThreadSummary } from '../../api/client';
import * as chat from '../chat/chat.css';
import * as tabCss from '../chat/chatTab.css';
import { Markdown } from '../chat/Markdown';
import { ScrollArea } from '../shell/ScrollArea';
import { HOUSE, SHELF, thread as threadKey, when } from './keys';

/**
 * The house's Chat (screen:next-house; the witness, 2026-11-16: "more like
 * the chat ui"): its threads as the conversation's messages are, oldest at
 * the top and the newest by the composer, each opening in place to its
 * trunk and every reply. The composer stays at the bottom: a title and
 * words start a thread; with one open, the words alone reply in it. Your
 * posts keep the household's rules (seshat#68, #69).
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
  const [open, setOpen] = useState<string | null>(null);
  const scroll = useRef<HTMLDivElement>(null);
  // The shelf comes newest first; the conversation reads down to now.
  const threads = (shelf.data?.pages ?? []).flatMap((p) => p.threads).reverse();
  const newest = threads[threads.length - 1]?.path;

  useEffect(() => {
    const el = scroll.current;
    if (el && open === null) el.scrollTop = el.scrollHeight;
  }, [newest, open]);

  const opened = threads.find((t) => t.path === open) ?? null;
  return (
    <div className={tabCss.tab}>
      <div className={chat.column}>
        <ScrollArea label="Threads" scrollRef={scroll}>
          <div className={chat.list}>
            {shelf.hasNextPage && (
              <button type="button" className={chat.linkButton} style={{ alignSelf: 'center' }} onClick={() => void shelf.fetchNextPage()}>
                Earlier threads
              </button>
            )}
            {shelf.isPending && <p className={chat.system}>Reading the house…</p>}
            {shelf.isError && <p className={chat.system}>The house could not be read.</p>}
            {shelf.data && threads.length === 0 && <p className={chat.system}>No threads yet. Start one below.</p>}
            {threads.map((t) => (
              <ThreadCard key={t.path} t={t} open={open === t.path} accountId={me.data?.account_id} onToggle={() => setOpen(open === t.path ? null : t.path)} />
            ))}
          </div>
        </ScrollArea>
        <Composer opened={opened} onPosted={setOpen} onClose={() => setOpen(null)} />
      </div>
    </div>
  );
}

function ThreadCard({ t, open, accountId, onToggle }: { t: HouseThreadSummary; open: boolean; accountId?: string; onToggle: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (open) ref.current?.scrollIntoView?.({ block: 'nearest' });
  }, [open]);
  const ballot = t.ballot ? (t.ballot.closed_at ? `ballot #${t.ballot.number} ${t.ballot.passed ? 'carried' : 'failed'}` : `ballot #${t.ballot.number} open`) : null;
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
  const b = doc.ballot;
  const mine = (p: HousePost) => p.meta.by_kind === 'witness' && p.meta.by_id === accountId;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {doc.trunk && <Words body={doc.trunk.body} />}
      {b && (
        <p className={chat.system}>
          Ballot #{b.number}: {b.closed_at ? `${b.passed ? 'carried' : 'failed'} ${when(b.closed_at)}` : `open until ${when(b.closes_at)}`} · {b.yes} yes, {b.no} no of {b.members}
        </p>
      )}
      {b && !b.closed_at && <Vote path={path} />}
      {(doc.replies ?? []).map((r) =>
        mine(r) ? (
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
            </span>
            <Words body={r.body} />
          </div>
        ),
      )}
    </div>
  );
}

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
