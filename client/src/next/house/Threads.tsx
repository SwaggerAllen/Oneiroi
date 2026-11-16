import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type HouseDoc, type HousePost, type HouseThreadSummary } from '../../api/client';
import { Card, Field, Said, TextArea } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { HousePage } from './common';
import { HOUSE, SHELF, thread as threadKey, when } from './keys';

/**
 * The house's chat (screen:next-house): the shared workspace's threads,
 * newest first, each opened whole with your reply; a new thread from here.
 * Your posts keep the household's rules (seshat#68, #69): the quota, once
 * in a thread a beat, and none if a ballot bars witnesses.
 */
export function Threads() {
  const [open, setOpen] = useState<string | null>(null);
  if (open) return <Thread path={open} onBack={() => setOpen(null)} />;
  return (
    <HousePage label="Threads" title="Threads" lede="The shared workspace: every thread the house has opened, newest first.">
      <Shelf onOpen={setOpen} />
      <NewThread onPosted={setOpen} />
    </HousePage>
  );
}

function Shelf({ onOpen }: { onOpen: (path: string) => void }) {
  const [from, setFrom] = useState(0);
  const shelf = useQuery({ queryKey: [...SHELF, from], queryFn: () => api.householdShelf(from), refetchInterval: 60_000 });
  if (shelf.isError) return <p className={css.note}>The house could not be read.</p>;
  if (!shelf.data) return <p className={css.note}>Reading the house…</p>;
  const threads = shelf.data.threads;
  return (
    <Card title={`${shelf.data.total} on the shelf`} label="The threads">
      {threads.length === 0 && <p className={css.note}>No threads yet.</p>}
      <ul className={css.list} aria-label="Threads">
        {threads.map((t) => (
          <Row key={t.path} t={t} onOpen={() => onOpen(t.path)} />
        ))}
      </ul>
      <div className={css.row}>
        {from > 0 && (
          <button type="button" className={css.quiet} onClick={() => setFrom(Math.max(0, from - 20))}>
            ‹ Newer
          </button>
        )}
        {shelf.data.next !== null && (
          <button type="button" className={css.quiet} onClick={() => setFrom(shelf.data.next ?? 0)}>
            Older ›
          </button>
        )}
      </div>
    </Card>
  );
}

function Row({ t, onOpen }: { t: HouseThreadSummary; onOpen: () => void }) {
  const ballot = t.ballot ? (t.ballot.closed_at ? ` · ballot #${t.ballot.number} ${t.ballot.passed ? 'carried' : 'failed'}` : ` · ballot #${t.ballot.number} open`) : '';
  return (
    <li className={css.item}>
      <button type="button" className={css.linkButton} onClick={onOpen}>
        {t.title}
      </button>
      <p className={css.meta}>
        {t.by} · {when(t.posted_at)} · {t.replies === 1 ? '1 reply' : `${t.replies} replies`}
        {t.last_reply_at ? `, last ${when(t.last_reply_at)}` : ''}
        {ballot}
      </p>
    </li>
  );
}

function NewThread({ onPosted }: { onPosted: (path: string) => void }) {
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const act = useAct();
  return (
    <Card title="A new thread">
      <form
        aria-label="A new thread"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(
            () =>
              api.householdPost({ title: title.trim(), content: content.trim() }).then((posted) => {
                setTitle('');
                setContent('');
                onPosted(posted.path);
                return 'Posted.';
              }),
            [...HOUSE],
          );
        }}
      >
        <Field label="Title" value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} />
        <TextArea label="Your words" value={content} onChange={(e) => setContent(e.target.value)} />
        <div className={css.row}>
          <button type="submit" className={css.primary} disabled={act.busy || !title.trim() || !content.trim()}>
            Post
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

/** One thread whole: its trunk, every reply in order, a ballot's vote, and your reply. */
export function Thread({ path, onBack }: { path: string; onBack: () => void }) {
  const doc = useQuery({ queryKey: threadKey(path), queryFn: () => api.householdRead(path), refetchInterval: 30_000 });
  return (
    <HousePage label="Thread" title={doc.data?.title ?? 'A thread'} lede={path}>
      <button type="button" className={css.back} onClick={onBack}>
        ‹ Threads
      </button>
      {doc.isError && <p className={css.note}>The thread could not be read.</p>}
      {!doc.data && !doc.isError && <p className={css.note}>Reading the thread…</p>}
      {doc.data && <Body doc={doc.data} />}
      {doc.data?.ballot && !doc.data.ballot.closed_at && <Vote path={path} />}
      {doc.data && <Reply path={path} />}
    </HousePage>
  );
}

function Body({ doc }: { doc: HouseDoc }) {
  if (!doc.trunk) return <pre className={css.pre}>{doc.content}</pre>;
  const b = doc.ballot;
  return (
    <>
      <Post post={doc.trunk} head={`${doc.trunk.meta.by} · ${when(doc.trunk.meta.posted_at)}`} />
      {b && (
        <Card title={`Ballot #${b.number}`}>
          <p className={css.text}>
            {b.closed_at ? `${b.passed ? 'Carried' : 'Failed'} ${when(b.closed_at)}` : `Open until ${when(b.closes_at)}`} · {b.yes} yes, {b.no} no of {b.members}
          </p>
        </Card>
      )}
      {(doc.replies ?? []).map((r) => (
        <Post
          key={r.path}
          post={r}
          head={`#${r.meta.reply} · ${r.meta.by} · ${when(r.meta.at)}${r.meta.vote ? ` · votes ${r.meta.vote}` : ''}${r.meta.in_reply_to ? ` · answering #${r.meta.in_reply_to}` : ''}`}
        />
      ))}
    </>
  );
}

function Post({ post, head }: { post: HousePost; head: string }) {
  return (
    <article className={css.card} aria-label={head}>
      <p className={css.meta}>{head}</p>
      <p className={css.text} style={{ whiteSpace: 'pre-wrap' }}>
        {post.body.trim()}
      </p>
    </article>
  );
}

function Vote({ path }: { path: string }) {
  const [words, setWords] = useState('');
  const act = useAct();
  const vote = (v: 'yes' | 'no') => void act.run(() => api.householdVote(path, v, words.trim()).then(() => `You voted ${v}.`), [...HOUSE]);
  return (
    <Card title="Your vote">
      <TextArea label="Words with your vote (optional)" value={words} onChange={(e) => setWords(e.target.value)} />
      <div className={css.row}>
        <button type="button" className={css.secondary} disabled={act.busy} onClick={() => vote('yes')}>
          Yes
        </button>
        <button type="button" className={css.secondary} disabled={act.busy} onClick={() => vote('no')}>
          No
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}

function Reply({ path }: { path: string }) {
  const [text, setText] = useState('');
  const act = useAct();
  return (
    <Card title="Your reply">
      <form
        aria-label="Reply to the thread"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(
            () =>
              api.householdReply(path, text.trim()).then((r) => {
                setText('');
                return `Replied: #${r.number}.`;
              }),
            [...HOUSE],
          );
        }}
      >
        <TextArea label="Reply" value={text} onChange={(e) => setText(e.target.value)} />
        <div className={css.row}>
          <button type="submit" className={css.primary} disabled={act.busy || !text.trim()}>
            Reply
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}
