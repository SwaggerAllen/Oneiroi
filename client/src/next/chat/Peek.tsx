import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Dialog, Heading, Modal, ModalOverlay } from 'react-aria-components';
import { api } from '../../api/client';
import { useWide } from '../shell/useWide';
import { formatHash } from '../state/routes';
import { documentPath, type Citation } from './cite';
import { Markdown } from './Markdown';
import * as css from './peek.css';
import { Retag } from './TurnTools';

export interface PeekProps {
  residentId: string;
  citation: Citation | null;
  onClose: () => void;
  onOpenFully: (c: Citation) => void;
  onCite: (c: Citation) => void;
}

/**
 * A citation opened where it was cited (ui-structures.md): a sheet over
 * the chat on a phone; on a wide screen a panel beside it that stays open
 * while you keep talking (decided 2026-11-10).
 */
export function Peek(props: PeekProps) {
  const wide = useWide();
  if (!props.citation) return null;
  if (wide) {
    return (
      <aside className={css.panel} aria-label={`Peek: ${props.citation.kind}/${props.citation.ref}`}>
        <PeekBody {...props} citation={props.citation} />
      </aside>
    );
  }
  return (
    <ModalOverlay className={css.overlay} isOpen onOpenChange={(open) => !open && props.onClose()} isDismissable>
      <Modal className={css.sheet}>
        <Dialog className={css.dialog} aria-label={`Peek: ${props.citation.kind}/${props.citation.ref}`}>
          <div className={css.grabber} aria-hidden />
          <PeekBody {...props} citation={props.citation} />
        </Dialog>
      </Modal>
    </ModalOverlay>
  );
}

function PeekBody({ residentId, citation, onClose, onOpenFully, onCite }: PeekProps & { citation: Citation }) {
  const path = documentPath(citation);
  const doc = useQuery({
    queryKey: ['resident', residentId, 'records', 'doc', path],
    queryFn: () => api.document(residentId, path as string),
    enabled: path !== null,
  });
  const bookmark = useQuery({
    queryKey: ['resident', residentId, 'memory', 'bookmark', citation.ref],
    // The body is {bookmark, span}; of the span only the anchor turn's
    // domain is kept (its words may be a private session's).
    queryFn: () =>
      api.bookmarkDetail(residentId, citation.ref).then((r) => ({
        ...r.bookmark,
        domain: r.span.find((m) => m.turn_ref === r.bookmark.anchor_ref && m.domain)?.domain?.slug ?? null,
      })),
    enabled: citation.kind === 'bookmark',
  });

  return (
    <>
      <div className={css.top}>
        <span className={css.path}>
          {citation.kind}/{citation.ref}
        </span>
        <button type="button" className={css.close} aria-label="Close" onClick={onClose}>
          ×
        </button>
      </div>
      <Heading slot="title" className={css.title}>
        {path ? (path.split('/').pop() ?? path).replace(/\.md$/, '') : `${citation.kind} ${citation.ref}`}
      </Heading>
      <div className={css.body}>
        {path !== null &&
          (doc.isPending ? (
            <p className={css.note}>Reading…</p>
          ) : doc.error ? (
            <p className={css.note}>This document couldn't be read here.</p>
          ) : (
            <Markdown text={doc.data?.content ?? ''} onCite={onCite} />
          ))}
        {citation.kind === 'bookmark' &&
          (bookmark.isPending ? (
            <p className={css.note}>Reading…</p>
          ) : bookmark.data ? (
            <>
              <p className={css.line}>{bookmark.data.private ? 'In a private session: its words are hers.' : bookmark.data.line}</p>
              {bookmark.data.summary && <p className={css.note}>{bookmark.data.summary}</p>}
              <p className={css.meta}>
                {new Date(bookmark.data.anchor_at).toLocaleString()} · {bookmark.data.tags.join(' · ')}
              </p>
              {!bookmark.data.private && <TurnDomain residentId={residentId} sessionKey={bookmark.data.session_key} turnRef={bookmark.data.anchor_ref} domain={bookmark.data.domain} />}
            </>
          ) : (
            <p className={css.note}>This bookmark couldn't be read here.</p>
          ))}
        {path === null && citation.kind !== 'bookmark' && (
          <p className={css.note}>This kind of record opens in Records.</p>
        )}
      </div>
      <div className={css.actions}>
        {citation.kind === 'bookmark' ? (
          // The moment itself, read in its conversation from the bookmark's
          // turn, with Read on past it (kumbukumbu#96, #99).
          bookmark.data &&
          !bookmark.data.private && (
            <a className={css.primary} style={{ textDecoration: 'none', textAlign: 'center' }} href={formatHash({ tab: 'chat', path: `turn/${bookmark.data.session_key}/${bookmark.data.anchor_ref}` })} onClick={onClose}>
              Read it in the conversation ›
            </a>
          )
        ) : (
          <button type="button" className={css.primary} onClick={() => onOpenFully(citation)}>
            Open in Records
          </button>
        )}
      </div>
    </>
  );
}

/** The bookmarked turn's domain, and moving it (kumbukumbu#99): the same picker as the chat's. */
function TurnDomain({ residentId, sessionKey, turnRef, domain }: { residentId: string; sessionKey: string; turnRef: string; domain: string | null }) {
  const [open, setOpen] = useState(false);
  const queries = useQueryClient();
  const retag = async (ref: string, to: string | null) => {
    await api.tagDomain(residentId, sessionKey, ref, to);
    await queries.invalidateQueries({ queryKey: ['resident', residentId] });
  };
  return (
    <>
      <button type="button" className={css.meta} style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', textDecoration: 'underline' }} aria-expanded={open} onClick={() => setOpen(!open)}>
        Domain: {domain ?? 'common room'}
      </button>
      {open && <Retag residentId={residentId} turnRef={turnRef} domain={domain} onRetag={retag} onDone={() => setOpen(false)} />}
    </>
  );
}
