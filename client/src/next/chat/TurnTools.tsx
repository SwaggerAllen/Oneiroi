import { useMutation, useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import * as css from '../inbox/inbox.css';

/**
 * On her reply: what she was given that turn (brain#, the context's parts
 * with their sizes and why each was there), and a bookmark you suggest
 * for the moment (kumbukumbu: she accepts or declines, in her words).
 */
export function TurnTools({ residentId, sessionKey, turnRef, residentName }: { residentId: string; sessionKey: string; turnRef: string; residentName: string }) {
  const [open, setOpen] = useState<'given' | 'bookmark' | null>(null);
  return (
    <span style={{ display: 'contents' }}>
      <button type="button" className={css.link} style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer' }} aria-expanded={open === 'given'} onClick={() => setOpen(open === 'given' ? null : 'given')}>
        What she was given
      </button>
      <button type="button" className={css.link} style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer' }} aria-expanded={open === 'bookmark'} onClick={() => setOpen(open === 'bookmark' ? null : 'bookmark')}>
        Suggest a bookmark
      </button>
      {open === 'given' && <Given residentId={residentId} turnRef={turnRef} />}
      {open === 'bookmark' && <Suggest residentId={residentId} sessionKey={sessionKey} turnRef={turnRef} residentName={residentName} onDone={() => setOpen(null)} />}
    </span>
  );
}

function Given({ residentId, turnRef }: { residentId: string; turnRef: string }) {
  const parts = useQuery({ queryKey: ['resident', residentId, 'chat', 'given', turnRef], queryFn: () => api.injections(residentId, turnRef), staleTime: Infinity });
  const total = (parts.data ?? []).reduce((n, p) => n + p.tokens, 0);
  return (
    <div className={css.panel} style={{ flexBasis: '100%' }}>
      {parts.isPending && <p className={css.note}>Reading what she was given…</p>}
      {parts.error && <p className={css.note}>{(parts.error as Error).message}</p>}
      {parts.data && <p className={css.meta}>{parts.data.length} parts · about {total.toLocaleString()} tokens</p>}
      {[...(parts.data ?? [])]
        .sort((a, b) => a.position - b.position)
        .map((p) => (
          <details key={`${p.position}-${p.label}`}>
            <summary className={css.summary}>
              {p.label} · {p.tokens.toLocaleString()} tokens
            </summary>
            <p className={css.note}>{p.reason}</p>
            {p.text ? <p className={css.text}>{p.text}</p> : <p className={css.note}>Its words aren't shown here.</p>}
          </details>
        ))}
    </div>
  );
}

function Suggest({ residentId, sessionKey, turnRef, residentName, onDone }: { residentId: string; sessionKey: string; turnRef: string; residentName: string; onDone: () => void }) {
  const [line, setLine] = useState('');
  const [note, setNote] = useState('');
  const send = useMutation({ mutationFn: () => api.proposeBookmark(residentId, sessionKey, turnRef, line.trim(), note.trim()), onSuccess: () => setTimeout(onDone, 1200) });
  return (
    <div className={css.panel} style={{ flexBasis: '100%' }}>
      <p className={css.note}>A bookmark is in {residentName}'s words; yours is a suggestion she accepts, rewrites or declines.</p>
      <input id={`bm-line-${turnRef}`} className={css.input} value={line} onChange={(e) => setLine(e.target.value)} placeholder="The line, as you'd put it" aria-label="The line" />
      <input id={`bm-note-${turnRef}`} className={css.input} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Why this moment (needed)" aria-label="Why this moment" />
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={!line.trim() || !note.trim() || send.isPending} onClick={() => send.mutate()}>
          Suggest it
        </button>
        {send.isSuccess && <span className={css.said}>Suggested.</span>}
      </div>
      {send.error && <p className={css.said}>{(send.error as Error).message}</p>}
    </div>
  );
}
