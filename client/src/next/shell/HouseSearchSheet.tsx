import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { Dialog, Heading, Input, Modal, ModalOverlay, SearchField, ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import { api, type HouseHit } from '../../api/client';
import { formatHash } from '../state/routes';
import { useShell } from '../state/store';
import * as css from './search.css';

const SCOPES = ['everything', 'threads', 'records', 'charter'] as const;
type Scope = (typeof SCOPES)[number];
const LABEL: Record<Scope, string> = { everything: 'Everything', threads: 'Threads', records: 'Records', charter: 'Charter' };
const KIND: Record<HouseHit['type'], string> = { thread: 'Thread', document: 'Record', charter: 'Charter' };

/**
 * The house's search (seshat#80; the witness, 2026-11-17: "the same
 * search functionality/ui as resident workspaces"): the same sheet, the
 * header's icon or ⌘K, scoped to what the house holds: its threads with
 * every reply, its records, its charter. Each hit opens in Records.
 */
export function HouseSearchSheet() {
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
    queryKey: ['household', 'search', scope, term],
    queryFn: () => api.householdSearch(term, scope),
    enabled: open && searchable,
    staleTime: 30_000,
  });
  const hits = results.data?.results;

  return (
    <ModalOverlay className={css.overlay} isOpen={open} onOpenChange={setOpen} isDismissable>
      <Modal className={css.modal}>
        <Dialog className={css.dialog} aria-label="Search the house">
          <Heading slot="title" className={css.visuallyHidden}>
            Search the house
          </Heading>
          <SearchField aria-label="Search" value={q} onChange={setQ} autoFocus className={css.field}>
            <Input className={css.input} placeholder="Search the house" />
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
                {LABEL[s]}
              </ToggleButton>
            ))}
          </ToggleButtonGroup>
          <div className={css.results} aria-live="polite">
            {searchable && results.isPending && <p className={css.note}>Searching…</p>}
            {searchable && results.error && <p className={css.note}>{(results.error as Error).message}</p>}
            {searchable && hits?.length === 0 && <p className={css.note}>Nothing found.</p>}
            {hits?.map((hit) => (
              <a key={hit.path} className={css.hit} href={formatHash({ tab: 'records', path: `doc/${hit.path}` })} onClick={() => setOpen(false)}>
                <span className={css.hitPath}>
                  {KIND[hit.type]} · {hit.title ?? hit.path}
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
