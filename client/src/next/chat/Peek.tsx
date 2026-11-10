import { useQuery } from '@tanstack/react-query';
import { Dialog, Heading, Modal, ModalOverlay } from 'react-aria-components';
import { api } from '../../api/client';
import { useWide } from '../shell/useWide';
import { documentPath, type Citation } from './cite';
import { Markdown } from './Markdown';
import * as css from './peek.css';

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
    queryFn: () => api.bookmark(residentId, citation.ref),
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
              <p className={css.line}>{bookmark.data.line}</p>
              {bookmark.data.summary && <p className={css.note}>{bookmark.data.summary}</p>}
              <p className={css.meta}>
                {new Date(bookmark.data.anchor_at).toLocaleString()} · {bookmark.data.tags.join(' · ')}
              </p>
            </>
          ) : (
            <p className={css.note}>This bookmark couldn't be read here.</p>
          ))}
        {path === null && citation.kind !== 'bookmark' && (
          <p className={css.note}>This kind of record opens in Records.</p>
        )}
      </div>
      <div className={css.actions}>
        <button type="button" className={css.primary} onClick={() => onOpenFully(citation)}>
          Open in Records
        </button>
      </div>
    </>
  );
}
