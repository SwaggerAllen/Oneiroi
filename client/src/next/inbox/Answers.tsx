import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { NeedsYouEntry } from '../../api/types';
import { formatHash } from '../state/routes';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import * as css from './inbox.css';

// The bell answers in place (screens/next-mail.md): an ask, a reply she
// drafted, a reply approved and waiting to be sent, a piece for review or
// for publishing. Every decision carries a note, which she reads first
// (agathos-daimon#35, xenia#13, seshat#42).

/** Whether the bell can answer this entry where it stands. */
export const answersInPlace = (kind: NeedsYouEntry['kind']) =>
  kind === 'ask' || kind === 'reply_to_approve' || kind === 'reply_to_send' || kind === 'piece_to_review' || kind === 'piece_to_publish';

function useDone() {
  const qc = useQueryClient();
  const { id } = useSubject();
  return () => {
    void qc.invalidateQueries({ queryKey: ['resident', id, 'bell'] });
    void qc.invalidateQueries({ queryKey: ['resident', id, 'mail'] });
  };
}

const fail = (e: unknown) => (e instanceof Error ? e.message : 'That did not go through.');

export function Answer({ entry }: { entry: NeedsYouEntry }) {
  switch (entry.kind) {
    case 'ask':
      return <AskAnswer number={Number(entry.ref)} />;
    case 'reply_to_approve':
    case 'reply_to_send':
      return <ReplyAnswer number={Number(entry.ref)} />;
    case 'piece_to_review':
    case 'piece_to_publish':
      return <PieceAnswer path={String(entry.ref)} />;
    default:
      return null;
  }
}

function AskAnswer({ number }: { number: number }) {
  const { id, name } = useSubject();
  const done = useDone();
  const asks = useQuery({ queryKey: ['resident', id, 'mail', 'asks'], queryFn: () => api.asks(id) });
  const ask = asks.data?.find((a) => a.number === number);
  const [note, setNote] = useState('');
  const answer = useMutation({
    mutationFn: (decision: 'approve' | 'decline' | 'noted') => api.answerAsk(id, number, decision, note.trim()),
    onSuccess: done,
  });
  if (!ask) return asks.isPending ? <p className={css.note}>Opening the ask…</p> : null;
  const ready = note.trim() !== '' && !answer.isPending;
  return (
    <div className={css.panel}>
      <p className={css.text}>
        {ask.kind === 'act' ? 'May I: ' : 'A tool: '}
        {ask.subject}
      </p>
      <p className={css.note}>Why: {ask.why}</p>
      {ask.kind === 'tool' && <p className={css.note}>Noting it grants nothing; it records that you read it.</p>}
      <input id={`ask-note-${number}`} className={css.input} value={note} onChange={(e) => setNote(e.target.value)} placeholder={`Your note to ${name} (needed)`} aria-label={`Your note to ${name}`} />
      <div className={css.row}>
        {ask.kind === 'act' ? (
          <>
            <button type="button" className={css.primary} disabled={!ready} onClick={() => answer.mutate('approve')}>
              Approve
            </button>
            <button type="button" className={css.quiet} disabled={!ready} onClick={() => answer.mutate('decline')}>
              Decline
            </button>
          </>
        ) : (
          <button type="button" className={css.primary} disabled={!ready} onClick={() => answer.mutate('noted')}>
            Noted
          </button>
        )}
      </div>
      {answer.error && <p className={css.said}>{fail(answer.error)}</p>}
    </div>
  );
}

function ReplyAnswer({ number }: { number: number }) {
  const { id, name } = useSubject();
  const done = useDone();
  const replies = useQuery({ queryKey: ['resident', id, 'mail', 'replies'], queryFn: () => api.replies(id) });
  const reply = replies.data?.find((r) => r.number === number);
  const [note, setNote] = useState('');
  const [url, setUrl] = useState('');
  const decide = useMutation({ mutationFn: (approve: boolean) => api.decideReply(id, number, approve, note.trim()), onSuccess: done });
  const sent = useMutation({ mutationFn: () => api.markSent(id, number, url.trim() || null), onSuccess: done });
  if (!reply) return replies.isPending ? <p className={css.note}>Opening the reply…</p> : null;
  return (
    <div className={css.panel}>
      <p className={css.meta}>
        On {reply.platform} from {reply.account} to {reply.to}
        {reply.in_reply_to ? ` · answering message #${reply.in_reply_to}` : ''}
      </p>
      <p className={css.text}>{reply.text}</p>
      {reply.state === 'drafted' ? (
        <>
          <input id={`reply-note-${number}`} className={css.input} value={note} onChange={(e) => setNote(e.target.value)} placeholder={`Your note to ${name} (needed)`} aria-label={`Your note to ${name}`} />
          <div className={css.row}>
            <button type="button" className={css.primary} disabled={!note.trim() || decide.isPending} onClick={() => decide.mutate(true)}>
              Approve to send
            </button>
            <button type="button" className={css.quiet} disabled={!note.trim() || decide.isPending} onClick={() => decide.mutate(false)}>
              Decline
            </button>
          </div>
        </>
      ) : reply.state === 'approved' ? (
        <>
          <p className={css.note}>Approved. Send it where it goes, then say so here.</p>
          <div className={css.row}>
            <input id={`reply-url-${number}`} className={css.input} value={url} onChange={(e) => setUrl(e.target.value)} placeholder="Where it is now (optional)" aria-label="Where it is now" />
            <button type="button" className={css.primary} disabled={sent.isPending} onClick={() => sent.mutate()}>
              I sent it
            </button>
          </div>
        </>
      ) : (
        <p className={css.note}>This reply is {reply.state}.</p>
      )}
      {(decide.error || sent.error) && <p className={css.said}>{fail(decide.error ?? sent.error)}</p>}
    </div>
  );
}

function PieceAnswer({ path }: { path: string }) {
  const { id, name } = useSubject();
  const done = useDone();
  const setOverlay = useShell((s) => s.setOverlay);
  const pieces = useQuery({ queryKey: ['resident', id, 'mail', 'pieces'], queryFn: () => api.pieces(id) });
  const review = pieces.data?.for_review.find((p) => p.path === path);
  const drafted = pieces.data?.drafted.find((p) => p.path === path) ?? pieces.data?.approved.find((p) => p.path === path);
  const [note, setNote] = useState('');
  const decide = useMutation({ mutationFn: (d: 'approve' | 'decline') => api.reviewPiece(id, path, d, note.trim()), onSuccess: done });
  const read = (
    <a className={css.link} href={formatHash({ tab: 'records', path: `doc/${path}` })} onClick={() => setOverlay(null)}>
      Read it in Records ›
    </a>
  );
  if (review)
    return (
      <div className={css.panel}>
        {review.last && (
          <p className={css.note}>
            Last time you {review.last.state === 'declined' ? 'declined it' : 'approved it'}: {review.last.note}
          </p>
        )}
        {read}
        <input id={`piece-note-${path}`} className={css.input} value={note} onChange={(e) => setNote(e.target.value)} placeholder={`Your note to ${name} (needed)`} aria-label={`Your note to ${name}`} />
        <div className={css.row}>
          <button type="button" className={css.primary} disabled={!note.trim() || decide.isPending} onClick={() => decide.mutate('approve')}>
            Approve
          </button>
          <button type="button" className={css.quiet} disabled={!note.trim() || decide.isPending} onClick={() => decide.mutate('decline')}>
            Decline
          </button>
        </div>
        {decide.error && <p className={css.said}>{fail(decide.error)}</p>}
      </div>
    );
  if (drafted)
    return (
      <div className={css.panel}>
        {drafted.draft_url ? (
          <>
            <p className={css.note}>A Substack draft is ready. Read it there and press Publish when it looks right; it is never published without you.</p>
            <a className={css.link} href={drafted.draft_url} target="_blank" rel="noreferrer">
              Open the draft on Substack ›
            </a>
          </>
        ) : (
          <p className={css.note}>Approved. The reader makes a Substack draft of it next.</p>
        )}
        {read}
      </div>
    );
  return pieces.isPending ? <p className={css.note}>Opening the piece…</p> : null;
}
