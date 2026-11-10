import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { Dialog, Heading, Input, Modal, ModalOverlay, SearchField, ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import { api } from '../../api/client';
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
 * wide screen, scopes to narrow it. Until the cross-kind search lands
 * (ui-server-work.md S3) it answers from the library's index.
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
  const searchable = term.length >= 2 && (scope === 'everything' || scope === 'records');
  const results = useQuery({
    queryKey: ['resident', residentId, 'search', scope, term],
    queryFn: () => api.librarySearch(residentId, term),
    enabled: open && searchable,
    staleTime: 30_000,
  });

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
            {!searchable && term.length >= 2 && <p className={css.note}>This scope arrives with the cross-kind search.</p>}
            {searchable && results.isPending && <p className={css.note}>Searching…</p>}
            {searchable && results.data?.length === 0 && <p className={css.note}>Nothing found.</p>}
            {results.data?.map((hit) => (
              <a key={`${hit.path}:${hit.text.slice(0, 20)}`} className={css.hit} href={`#/records/doc/${hit.path}`} onClick={() => setOpen(false)}>
                <span className={css.hitPath}>{hit.path}</span>
                <span className={css.hitText}>{hit.text.slice(0, 160)}</span>
              </a>
            ))}
          </div>
        </Dialog>
      </Modal>
    </ModalOverlay>
  );
}
