import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { Dialog, Heading, Input, Modal, ModalOverlay, SearchField, ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import { api, type SearchResult } from '../../api/client';
import { formatHash } from '../state/routes';
import { useShell } from '../state/store';
import * as css from './search.css';

const SCOPES = ['everything', 'records', 'bookmarks', 'scenes', 'words', 'as-she-sees-it'] as const;
type Scope = (typeof SCOPES)[number];
const LABEL: Record<Scope, string> = {
  everything: 'Everything',
  records: 'Records',
  bookmarks: 'Bookmarks',
  scenes: 'Scenes',
  words: 'Her words',
  'as-she-sees-it': 'As she sees it',
};

/**
 * The one search (ui-structures.md): the header's icon on a phone, ⌘K on a
 * wide screen, scopes to narrow it. It answers from the cross-kind search
 * (kumbukumbu#59): typed results, ranked within a scope, interleaved for
 * everything. Each opens where it lives.
 */
export function SearchSheet({ residentId, residentName }: { residentId: string; residentName: string }) {
  const open = useShell((s) => s.searchOpen);
  const setOpen = useShell((s) => s.setSearchOpen);
  const [q, setQ] = useState('');
  const [scope, setScope] = useState<Scope>('everything');

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setOpen(true);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [setOpen]);

  const term = q.trim();
  const searchable = term.length >= 2;
  const results = useQuery({
    queryKey: ['resident', residentId, 'search', scope, term],
    queryFn: () => api.search(residentId, term, scope),
    enabled: open && searchable,
    staleTime: 30_000,
  });
  const hits = results.data?.results;

  return (
    <ModalOverlay className={css.overlay} isOpen={open} onOpenChange={setOpen} isDismissable>
      <Modal className={css.modal}>
        <Dialog className={css.dialog} aria-label="Search everything">
          <Heading slot="title" className={css.visuallyHidden}>
            Search everything
          </Heading>
          <SearchField aria-label="Search" value={q} onChange={setQ} autoFocus className={css.field}>
            <Input className={css.input} placeholder={`Search ${residentName}'s life`} />
          </SearchField>
          <ToggleButtonGroup
            aria-label="Narrow the search"
            selectionMode="single"
            disallowEmptySelection
            selectedKeys={[scope]}
            onSelectionChange={(keys) => setScope([...keys][0] as Scope)}
            className={css.scopes}
          >
            {SCOPES.map((s) => (
              <ToggleButton key={s} id={s} className={css.scope}>
                {s === 'as-she-sees-it' ? `As ${residentName} sees it` : LABEL[s]}
              </ToggleButton>
            ))}
          </ToggleButtonGroup>
          <div className={css.results} aria-live="polite">
            {searchable && results.isPending && <p className={css.note}>Searching…</p>}
            {searchable && results.error && <p className={css.note}>{(results.error as Error).message}</p>}
            {searchable && hits?.length === 0 && <p className={css.note}>Nothing found.</p>}
            {hits?.map((hit, i) => (
              <a key={`${hit.type}:${i}`} className={css.hit} href={hrefOf(hit)} onClick={() => setOpen(false)}>
                <span className={css.hitPath}>
                  {KIND[hit.type]} · {hit.title}
                  {hit.at ? ` · ${hit.at.slice(0, 10)}` : ''}
                </span>
                <span className={css.hitText}>{hit.snippet}</span>
              </a>
            ))}
          </div>
        </Dialog>
      </Modal>
    </ModalOverlay>
  );
}

const KIND: Record<SearchResult['type'], string> = { transcript: 'Words', document: 'Record', bookmark: 'Bookmark', scene: 'Scene' };

/** Where a result lives: a turn in the conversation, a document, a bookmark. */
function hrefOf(hit: SearchResult): string {
  switch (hit.type) {
    case 'transcript':
      return formatHash({ tab: 'chat', path: `turn/${hit.ref.session_key}/${hit.ref.turn_ref}` });
    case 'bookmark':
      return formatHash({ tab: 'records', path: `cite/bookmark/${hit.ref.number}` });
    case 'document':
    case 'scene':
      return formatHash({ tab: 'records', path: `doc/${hit.ref.path}` });
  }
}
