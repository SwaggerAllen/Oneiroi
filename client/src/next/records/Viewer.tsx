import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Button, Menu, MenuItem, MenuTrigger, Popover } from 'react-aria-components';
import { api, RequestFailed } from '../../api/client';
import { Markdown } from '../chat/Markdown';
import { targetsFor, type Citation } from '../chat/cite';
import * as reactCss from '../chat/reacts.css';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './records.css';

/**
 * A record, read (ui-structures.md D): markdown with her citations as
 * links that open the cited record in this tab's stack, what it cites,
 * and what cites it; its history, the editor under a lease, and reacts
 * on the page itself (seshat#54, #55, kumbukumbu#61).
 */
export function Viewer({
  residentId,
  slug,
  path,
  onCite,
  onOpen,
  onBack,
  onGone,
}: {
  residentId: string;
  slug: string;
  path: string;
  onCite: (c: Citation) => void;
  onOpen: (path: string) => void;
  onBack: () => void;
  /** After a remove: the record is gone, so not back to it. */
  onGone: () => void;
}) {
  const read = useQuery({
    queryKey: ['resident', residentId, 'records', 'doc', path, 'full'],
    queryFn: () => api.documentRead(residentId, path),
    // A document just written or moved is registered a moment later.
    retry: (n, e) => n < 4 && e instanceof RequestFailed && e.status === 404,
    retryDelay: 600,
  });
  const targets = targetsFor(slug, path);
  const citedBy = useQuery({
    queryKey: ['resident', residentId, 'records', 'cited-by', path],
    queryFn: () => Promise.all(targets.map((t) => api.citedBy(residentId, t))).then((rows) => rows.flat()),
  });

  const { name } = useSubject();
  const doc = read.data?.document;
  const lease = read.data?.lease ?? null;
  const folder = path.split('/')[0];
  const fromPaths = [...new Set((citedBy.data ?? []).map((r) => r.from_path))];

  return (
    <ScrollArea label={path}>
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ {folder}
        </button>
        <div className={css.meta}>
          {targets[targets.length - 1]}
          {doc ? ` · v${doc.versions}` : ''}
          {doc?.written_at ? ` · ${new Date(doc.written_at).toLocaleString()}` : ''}
          {doc?.written_by ? ` · by ${doc.written_by}` : ''}
        </div>
        <h1 className={css.title}>{doc?.title ?? path.split('/').pop()?.replace(/\.md$/, '')}</h1>
        <div className={css.tools}>
          <button type="button" className={css.quiet} onClick={() => onOpen(`history/${path}`)}>
            History
          </button>
          <button type="button" className={css.quiet} onClick={() => onOpen(`edit/${path}`)}>
            Edit
          </button>
          <a className={css.quiet} style={{ display: 'inline-flex', alignItems: 'center', textDecoration: 'none' }} href={api.downloadUrl(residentId, path)} download>
            Download
          </a>
          <DocActions residentId={residentId} path={path} kind={doc?.kind ?? folder} onMoved={(to) => onOpen(`doc/${to}`)} onRemoved={onGone} />
          <DocReacts residentId={residentId} path={path} residentName={name} />
          {lease && (
            <span className={css.leaseNote}>
              {lease.state === 'taken' ? `${name} took the lease to write` : lease.waiting_at ? `${name} is waiting on this file` : 'Open in an editor'}
            </span>
          )}
        </div>
        {read.isPending && <p className={css.note}>Reading…</p>}
        {read.error && <p className={css.note}>This record couldn't be read.</p>}
        {read.data && <Markdown text={read.data.content} onCite={onCite} />}

        {(read.data?.references.length ?? 0) > 0 && (
          <div className={css.links}>
            <span className={css.linksLabel}>CITES</span>
            {read.data?.references.map((r, i) => (
              <button
                key={`${r.target}-${i}`}
                type="button"
                className={css.chip}
                data-broken={!r.resolved}
                title={r.resolved ? (r.label ?? r.target) : (r.reason ?? 'unresolved')}
                onClick={() => onCite({ slug: r.target.split(':')[0], kind: r.kind, ref: r.ref })}
              >
                {r.kind}/{r.ref}
              </button>
            ))}
          </div>
        )}
        {fromPaths.length > 0 && (
          <div className={css.links}>
            <span className={css.linksLabel}>CITED BY</span>
            {fromPaths.map((from) => (
              <button key={from} type="button" className={css.chip} onClick={() => onOpen(`doc/${from}`)}>
                {from}
              </button>
            ))}
          </div>
        )}
      </div>
    </ScrollArea>
  );
}

/** Reacts on the page itself (kumbukumbu#61): a react wakes nobody. */
function DocReacts({ residentId, path, residentName }: { residentId: string; path: string; residentName: string }) {
  const qc = useQueryClient();
  const key = ['resident', residentId, 'records', 'reacts', path];
  const reacts = useQuery({ queryKey: key, queryFn: () => api.documentReacts(residentId, path) });
  const vocabulary = useQuery({
    queryKey: ['resident', residentId, 'soul', 'reacts-vocabulary'],
    queryFn: () => api.reactVocabulary(residentId),
    staleTime: 10 * 60_000,
  });
  const add = useMutation({
    mutationFn: (emoji: string) => api.react(residentId, { kind: 'document', path }, emoji),
    onSuccess: () => qc.invalidateQueries({ queryKey: key }),
  });
  const meaning = new Map((vocabulary.data ?? []).map((v) => [v.emoji, v.meaning]));
  return (
    <div className={reactCss.row}>
      {(reacts.data ?? []).map((r) => (
        <span key={r.number} className={r.by === 'witness' ? reactCss.mine : reactCss.hers} title={meaning.get(r.emoji)}>
          {r.emoji} {r.by === 'witness' ? 'you' : residentName}
        </span>
      ))}
      <MenuTrigger>
        <Button className={reactCss.add} aria-label="React to this record">
          React
        </Button>
        <Popover className={reactCss.popover} placement="bottom start">
          <Menu className={reactCss.menu} aria-label="Reacts" onAction={(emoji) => add.mutate(String(emoji))}>
            {(vocabulary.data ?? []).map((v) => (
              <MenuItem key={v.emoji} id={v.emoji} className={reactCss.item} textValue={v.meaning}>
                <span className={reactCss.emoji}>{v.emoji}</span>
                <span>{v.meaning}</span>
              </MenuItem>
            ))}
          </Menu>
        </Popover>
      </MenuTrigger>
    </div>
  );
}

// Kinds whose documents stay where they are (the old library's rule; the server says the rest).
const STAYS = new Set(['mail', 'feeds', 'correspondence', 'journal', 'memory', 'originals', 'scenes']);

/** Move to another path, and so another kind (seshat#39); remove a scratch or human document (seshat#33). */
function DocActions({ residentId, path, kind, onMoved, onRemoved }: { residentId: string; path: string; kind: string; onMoved: (to: string) => void; onRemoved: () => void }) {
  const qc = useQueryClient();
  const [moving, setMoving] = useState(false);
  const [to, setTo] = useState(path);
  const [confirming, setConfirming] = useState(false);
  const refresh = () => void qc.invalidateQueries({ queryKey: ['resident', residentId, 'records'] });
  const move = useMutation({ mutationFn: () => api.moveDocument(residentId, path, to.trim()), onSuccess: (r) => (refresh(), onMoved(r.to)) });
  const remove = useMutation({ mutationFn: () => api.removeDocument(residentId, path), onSuccess: () => (refresh(), onRemoved()) });
  const removable = kind === 'scratch' || kind === 'human';
  return (
    <>
      {!STAYS.has(kind) && (
        <button type="button" className={css.quiet} aria-expanded={moving} onClick={() => setMoving(!moving)}>
          Move
        </button>
      )}
      {removable && (
        <button type="button" className={css.quiet} onClick={() => (confirming ? remove.mutate() : setConfirming(true))} onBlur={() => setConfirming(false)}>
          {confirming ? 'Remove it for good' : 'Remove'}
        </button>
      )}
      {moving && (
        <span className={css.restore} style={{ flexBasis: '100%' }}>
          <input id="move-to" className={css.input} value={to} onChange={(e) => setTo(e.target.value)} aria-label="Move to" />
          <button type="button" className={css.action} disabled={!to.trim() || to.trim() === path || move.isPending} onClick={() => move.mutate()}>
            Move it
          </button>
        </span>
      )}
      {(move.error || remove.error) && <span className={css.note}>{((move.error ?? remove.error) as Error).message}</span>}
    </>
  );
}
