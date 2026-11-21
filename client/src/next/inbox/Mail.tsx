import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { Block, CorrespondenceMessage, HouseLetter } from '../../api/types';
import { isOpen, letterState, stateLine } from './letters';
import { fromLine, mailThreads, type MailThread } from './mailThreads';
import { threads } from './threads';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './inbox.css';

const when = (at: string) => new Date(at).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
const firstLine = (text: string) => {
  const line = text.split('\n').find((l) => l.trim() !== '') ?? '';
  return line.length > 140 ? `${line.slice(0, 140)}…` : line;
};
const fail = (e: unknown) => (e instanceof Error ? e.message : 'That did not go through.');

/**
 * Mail (screens/next-mail.md): the letters between her conversations,
 * open first, with one of yours to write (kumbukumbu#44); the mail that
 * reached her from outside, by thread, her replies in it, with a way to
 * block a sender (xenia#12); and who is blocked. The replies waiting on
 * you are answered in the bell.
 */
export function Mail() {
  const { id, name } = useSubject();
  const letters = useQuery({ queryKey: ['resident', id, 'mail', 'letters'], queryFn: () => api.letters(id) });
  const messages = useQuery({ queryKey: ['resident', id, 'mail', 'correspondence'], queryFn: () => api.correspondence(id) });
  const replies = useQuery({ queryKey: ['resident', id, 'mail', 'replies'], queryFn: () => api.replies(id) });
  const blocks = useQuery({ queryKey: ['resident', id, 'mail', 'blocks'], queryFn: () => api.blocks(id) });

  return (
    <ScrollArea label="Mail">
      <div className={css.page}>
        <Letters name={name} letters={letters.data ?? []} pending={letters.isPending} />
        <Outside name={name} messages={messages.data ?? []} replies={replies.data ?? []} blocks={blocks.data ?? []} pending={messages.isPending} />
        <Blocked name={name} blocks={blocks.data ?? []} />
      </div>
    </ScrollArea>
  );
}

function Letters({ name, letters, pending }: { name: string; letters: HouseLetter[]; pending: boolean }) {
  const [all, setAll] = useState(false);
  // Grouped as threads (the witness, 2026-11-19): a thread is open while
  // its newest letter still asks something of someone.
  const threads = mailThreads(letters);
  const open = threads.filter((t) => isOpen(letterState(t.letters[t.letters.length - 1], letters)));
  const shown = all ? threads : open;
  return (
    <section className={css.page} style={{ padding: 0, gap: 10 }} aria-label="Letters">
      <h2 className={css.heading}>LETTERS BETWEEN {name.toUpperCase()}'S CONVERSATIONS</h2>
      <div className={css.segment} role="group" aria-label="Which letters">
        <button type="button" className={css.segmentButton} aria-pressed={!all} onClick={() => setAll(false)}>
          Open · {open.length}
        </button>
        <button type="button" className={css.segmentButton} aria-pressed={all} onClick={() => setAll(true)}>
          All · {threads.length}
        </button>
      </div>
      <WriteLetter name={name} />
      {pending && <p className={css.note}>Reading the letters…</p>}
      {!pending && shown.length === 0 && <p className={css.note}>{letters.length === 0 ? 'No letters yet.' : 'Every letter has been answered.'}</p>}
      {shown.map((t) => (
        <MailThreadCard key={t.root} thread={t} all={letters} />
      ))}
    </section>
  );
}

/**
 * One mail thread as a card (the chat tab shows the same card for a
 * letter wake): its letters oldest first, each saying plainly who it is
 * from, her own marked as hers (report #22), and where it stands.
 */
export function MailThreadCard({ thread, all, open: startOpen = false }: { thread: MailThread; all: HouseLetter[]; open?: boolean }) {
  const last = thread.letters[thread.letters.length - 1];
  const state = letterState(last, all);
  const others = [...new Set(thread.letters.filter((l) => l.origin !== 'own').map(fromLine))];
  return (
    <article className={css.card} aria-label={`Mail thread #${thread.root}`}>
      <details open={startOpen}>
        <summary className={css.summary}>
          {thread.letters[0].text === null ? 'A sealed letter' : firstLine(thread.letters[0].text)}
          <span className={css.meta}>
            {' '}
            · {thread.letters.length === 1 ? '1 letter' : `${thread.letters.length} letters`}
            {others.length > 0 ? ` · with ${others.join(', ')}` : ''} · {when(last.sent_at)}
          </span>
        </summary>
        <div className={css.thread} style={{ marginTop: 8 }}>
          {thread.letters.map((l) => (
            <div key={l.number} className={l.origin === 'own' ? css.hers : undefined} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              <p className={css.meta}>
                #{l.number} · {l.origin === 'own' ? 'Hers, ' : ''}from {fromLine(l)} → {l.to} · {when(l.sent_at)}
              </p>
              {l.text === null ? <p className={css.note}>Sealed between them: you see that it was sent, never its words.</p> : <p className={css.text}>{l.text}</p>}
              {l.keepsake && <p className={css.note}>With a keepsake: {l.keepsake}</p>}
            </div>
          ))}
        </div>
      </details>
      <span className={isOpen(state) ? css.open : css.closed}>{stateLine(state)}</span>
    </article>
  );
}

/** A letter from you (kumbukumbu#44): to one of her conversations by name, to Free time, or to the house. */
function WriteLetter({ name }: { name: string }) {
  const { id } = useSubject();
  const qc = useQueryClient();
  const addresses = useQuery({ queryKey: ['resident', id, 'mail', 'addresses'], queryFn: () => api.letterAddresses(id) });
  const list = addresses.data ?? [];
  const [to, setTo] = useState<string | null>(null);
  const [text, setText] = useState('');
  const chosen = to ?? (list.includes('Free time') ? 'Free time' : list[0]);
  const send = useMutation({
    mutationFn: () => api.sendLetter(id, chosen, text.trim()),
    onSuccess: () => {
      setText('');
      void qc.invalidateQueries({ queryKey: ['resident', id, 'mail', 'letters'] });
    },
  });
  if (list.length === 0) return null;
  const label = (a: string) => (a === 'house' ? `house (any of ${name}'s conversations)` : a === 'Free time' ? `Free time (${name}'s next free time)` : a);
  return (
    <details className={css.card}>
      <summary className={css.summary}>Write a letter</summary>
      <div className={css.panel} style={{ borderTop: 'none' }}>
        <select id="letter-to" className={css.input} value={chosen} onChange={(e) => setTo(e.target.value)} aria-label="To">
          {list.map((a) => (
            <option key={a} value={a}>
              {label(a)}
            </option>
          ))}
        </select>
        <textarea id="letter-text" className={css.area} value={text} onChange={(e) => setText(e.target.value)} aria-label="Letter" />
        <div className={css.row}>
          <button type="button" className={css.primary} disabled={!text.trim() || send.isPending} onClick={() => send.mutate()}>
            Send the letter
          </button>
          {send.isSuccess && <span className={css.said}>Sent.</span>}
        </div>
        {send.error && <p className={css.said}>{fail(send.error)}</p>}
      </div>
    </details>
  );
}

function Outside({
  name,
  messages,
  replies,
  blocks,
  pending,
}: {
  name: string;
  messages: CorrespondenceMessage[];
  replies: Parameters<typeof threads>[1];
  blocks: Block[];
  pending: boolean;
}) {
  const blocked = new Set(blocks.map((b) => `${b.platform}:${b.identity}`));
  const all = threads(messages, replies);
  return (
    <section className={css.page} style={{ padding: 0, gap: 10 }} aria-label="From outside">
      <h2 className={css.heading}>FROM OUTSIDE THE HOUSE</h2>
      <p className={css.note}>Messages to {name} from outside, by thread, with {name}'s replies in them. The replies waiting on you are in the bell.</p>
      {pending && <p className={css.note}>Reading the mail…</p>}
      {!pending && all.length === 0 && <p className={css.note}>None yet.</p>}
      {all.map((t) => (
        <article key={t.key} className={css.card} aria-label={`Thread with ${t.with}`}>
          <p className={css.meta}>
            With {t.with} · {t.entries.length} {t.entries.length === 1 ? 'message' : 'messages'}
          </p>
          <div className={css.thread}>
            {t.entries.map((e) =>
              e.kind === 'message' ? (
                <Message key={`m${e.message.number}`} message={e.message} blocked={blocked.has(`${e.message.platform}:${e.message.sender}`)} />
              ) : (
                <div key={`r${e.reply.number}`} className={`${css.thread} ${css.hers}`}>
                  <p className={css.meta}>
                    {name}'s reply #{e.reply.number} · {e.reply.state}
                    {e.reply.url ? ' · ' : ''}
                    {e.reply.url && (
                      <a className={css.link} href={e.reply.url} target="_blank" rel="noreferrer">
                        where it is
                      </a>
                    )}
                  </p>
                  <details>
                    <summary className={css.summary}>{firstLine(e.reply.text)}</summary>
                    <p className={css.text} style={{ marginTop: 8 }}>
                      {e.reply.text}
                    </p>
                  </details>
                </div>
              ),
            )}
          </div>
        </article>
      ))}
    </section>
  );
}

function Message({ message: m, blocked }: { message: CorrespondenceMessage; blocked: boolean }) {
  const { id } = useSubject();
  const qc = useQueryClient();
  const [blocking, setBlocking] = useState(false);
  const [note, setNote] = useState('');
  const block = useMutation({
    mutationFn: () => api.block(id, m.platform, m.sender, m.sender_name, note.trim()),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['resident', id, 'mail'] }),
  });
  const from = m.sender_name ? `${m.sender_name} <${m.sender}>` : m.sender;
  if (m.state === 'blocked')
    return (
      <p className={css.meta}>
        #{m.number} · {m.platform} · from {m.sender} · {when(m.sent_at)} · blocked, not kept
      </p>
    );
  return (
    <div className={css.thread} style={{ borderLeft: 'none', paddingLeft: 0 }}>
      <p className={css.meta}>
        #{m.number} · {m.platform} · from {from} · {when(m.sent_at)} · {m.read_at ? 'read' : 'unread'}
        {m.verified ? '' : ' · sender not verified'}
      </p>
      {m.subject && <p className={css.text} style={{ fontWeight: 600 }}>{m.subject}</p>}
      <details>
        <summary className={css.summary}>{firstLine(m.text ?? '')}</summary>
        <p className={css.text} style={{ marginTop: 8 }}>
          {m.text}
        </p>
      </details>
      {!blocked &&
        (blocking ? (
          <div className={css.row}>
            <input id={`block-note-${m.number}`} className={css.input} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Why (needed)" aria-label="Why block them" />
            <button type="button" className={css.quiet} disabled={!note.trim() || block.isPending} onClick={() => block.mutate()}>
              Block {m.sender}
            </button>
          </div>
        ) : (
          <div>
            <button type="button" className={css.quiet} onClick={() => setBlocking(true)}>
              Block sender
            </button>
          </div>
        ))}
      {block.error && <p className={css.said}>{fail(block.error)}</p>}
    </div>
  );
}

/** The blocks (xenia#12): counted and never kept; each lifted only by whoever set it. */
function Blocked({ name, blocks }: { name: string; blocks: Block[] }) {
  return (
    <section className={css.page} style={{ padding: 0, gap: 10 }} aria-label="Blocked">
      <h2 className={css.heading}>BLOCKED</h2>
      <p className={css.note}>Their messages are counted and never kept. Each block is lifted only by whoever set it.</p>
      {blocks.length === 0 && <p className={css.note}>Nobody.</p>}
      {blocks.map((b) => (
        <BlockRow key={`${b.platform}:${b.identity}`} name={name} block={b} />
      ))}
    </section>
  );
}

function BlockRow({ name, block: b }: { name: string; block: Block }) {
  const { id } = useSubject();
  const qc = useQueryClient();
  const [lifting, setLifting] = useState(false);
  const [note, setNote] = useState('');
  const lift = useMutation({
    mutationFn: () => api.unblock(id, b.platform, b.identity, note.trim()),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['resident', id, 'mail'] }),
  });
  const mine = b.blocked_by === 'witness';
  return (
    <div className={css.card}>
      <p className={css.text}>
        {b.name ? `${b.name} · ` : ''}
        {b.identity}
      </p>
      <p className={css.note}>
        on {b.platform} · {mine ? 'by you' : `by ${name}`}: {b.note}
      </p>
      {mine &&
        (lifting ? (
          <div className={css.row}>
            <input id={`lift-note-${b.identity}`} className={css.input} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Why lift it (needed)" aria-label="Why lift it" />
            <button type="button" className={css.quiet} disabled={!note.trim() || lift.isPending} onClick={() => lift.mutate()}>
              Unblock {b.identity}
            </button>
          </div>
        ) : (
          <div>
            <button type="button" className={css.quiet} onClick={() => setLifting(true)}>
              Lift
            </button>
          </div>
        ))}
      {lift.error && <p className={css.said}>{fail(lift.error)}</p>}
    </div>
  );
}
