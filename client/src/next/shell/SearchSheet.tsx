import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { Dialog, Heading, Input, Modal, ModalOverlay, SearchField, ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import { api, type SearchResult } from '../../api/client';
import { formatHash } from '../state/routes';
import { activeCount, CONVERSATIONS, FILTERED, NO_FILTERS, sorts, toParams, type Filters } from './searchFilters';
import { useShell } from '../state/store';
import * as css from './search.css';

const SCOPES = ['everything', 'records', 'bookmarks', 'scenes', 'words', 'as-she-sees-it'] as const;
type Scope = (typeof SCOPES)[number];
const LABEL: Record<Scope, string> = {
  everything: 'Everything',
  records: 'Records',
  bookmarks: 'Bookmarks',
  scenes: 'Scenes',
  words: 'Transcripts',
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
  // Each scope narrows behind Filter (kumbukumbu#67, #69): days in this
  // browser's zone, both included; transcripts page by 50.
  const [filters, setFilters] = useState<Filters>(NO_FILTERS);
  const [showFilters, setShowFilters] = useState(false);
  const [page, setPage] = useState(1);
  const set = <K extends keyof Filters>(key: K, value: Filters[K]) => {
    setFilters((f) => ({ ...f, [key]: value }));
    setPage(1);
  };
  const filterable = (FILTERED as readonly string[]).includes(scope);
  const kinds = useQuery({ queryKey: ['resident', residentId, 'kinds'], queryFn: () => api.kinds(residentId), enabled: open && showFilters && scope === 'records' });
  const tags = useQuery({ queryKey: ['resident', residentId, 'tags'], queryFn: () => api.tags(residentId), enabled: open && showFilters && scope === 'bookmarks' });

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
  const narrow = toParams(scope, filters, page);
  const results = useQuery({
    queryKey: ['resident', residentId, 'search', scope, term, narrow],
    queryFn: () => api.search(residentId, term, scope, narrow),
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
          <SearchField
            aria-label="Search"
            value={q}
            onChange={(value) => {
              setQ(value);
              setPage(1);
            }}
            autoFocus
            className={css.field}
          >
            <Input className={css.input} placeholder={`Search ${residentName}'s life`} />
          </SearchField>
          <ToggleButtonGroup
            aria-label="Narrow the search"
            selectionMode="single"
            disallowEmptySelection
            selectedKeys={[scope]}
            onSelectionChange={(keys) => {
              setScope([...keys][0] as Scope);
              setPage(1);
            }}
            className={css.scopes}
          >
            {SCOPES.map((s) => (
              <ToggleButton key={s} id={s} className={css.scope}>
                {s === 'as-she-sees-it' ? `As ${residentName} sees it` : LABEL[s]}
              </ToggleButton>
            ))}
          </ToggleButtonGroup>
          {filterable && (
            <div className={css.filters}>
              <button type="button" className={css.scope} aria-expanded={showFilters} onClick={() => setShowFilters((v) => !v)}>
                Filter{activeCount(scope, filters) > 0 ? ` · ${activeCount(scope, filters)}` : ''}
              </button>
              {activeCount(scope, filters) > 0 && (
                <button
                  type="button"
                  className={css.scope}
                  onClick={() => {
                    setFilters(NO_FILTERS);
                    setPage(1);
                  }}
                >
                  Clear
                </button>
              )}
            </div>
          )}
          {filterable && showFilters && (
            <div className={css.filterPanel} role="group" aria-label="Filters">
              <div className={css.filters}>
                <label className={css.filter}>
                  From
                  <input type="date" className={css.filterInput} value={filters.from} onChange={(e) => set('from', e.target.value)} />
                </label>
                <label className={css.filter}>
                  To
                  <input type="date" className={css.filterInput} value={filters.to} onChange={(e) => set('to', e.target.value)} />
                </label>
                {scope === 'records' && (
                  <label className={css.filter}>
                    By
                    <select className={css.filterInput} value={filters.date} onChange={(e) => set('date', e.target.value as Filters['date'])}>
                      <option value="updated">Updated</option>
                      <option value="created">Created</option>
                    </select>
                  </label>
                )}
                <label className={css.filter}>
                  Order
                  <select className={css.filterInput} value={sorts(scope).includes(filters.sort) ? filters.sort : sorts(scope)[0]} onChange={(e) => set('sort', e.target.value as Filters['sort'])}>
                    {sorts(scope).map((s) => (
                      <option key={s} value={s}>
                        {s === 'relevance' ? 'Best match' : s === 'newest' ? 'Newest first' : 'Oldest first'}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              {scope === 'records' && (
                <>
                  <div className={css.filters}>
                    <label className={css.filter}>
                      Written by
                      <select className={css.filterInput} value={filters.author} onChange={(e) => set('author', e.target.value as Filters['author'])}>
                        <option value="">Anyone</option>
                        <option value="resident">{residentName}</option>
                        <option value="witness">You</option>
                        <option value="platform">The platform</option>
                      </select>
                    </label>
                    <label className={css.filter}>
                      Status
                      <input className={css.filterInput} value={filters.status} onChange={(e) => set('status', e.target.value)} placeholder="draft, review…" />
                    </label>
                  </div>
                  <fieldset className={css.checks}>
                    <legend className={css.filter}>Kinds</legend>
                    {(kinds.data?.kinds ?? []).map((k) => (
                      <label key={k.kind} className={css.check}>
                        <input
                          type="checkbox"
                          checked={filters.kinds.includes(k.kind)}
                          onChange={(e) => set('kinds', e.target.checked ? [...filters.kinds, k.kind] : filters.kinds.filter((x) => x !== k.kind))}
                        />
                        {k.label}
                      </label>
                    ))}
                  </fieldset>
                </>
              )}
              {scope === 'words' && (
                <>
                  <div className={css.filters}>
                    <label className={css.filter}>
                      Said by
                      <select className={css.filterInput} value={filters.who} onChange={(e) => set('who', e.target.value as Filters['who'])}>
                        <option value="">Anyone</option>
                        <option value="resident">{residentName}</option>
                        <option value="witness">You</option>
                        <option value="platform">The platform</option>
                      </select>
                    </label>
                  </div>
                  <fieldset className={css.checks}>
                    <legend className={css.filter}>Conversations</legend>
                    {CONVERSATIONS.map(([kind, label]) => (
                      <label key={kind} className={css.check}>
                        <input
                          type="checkbox"
                          checked={filters.conversations.includes(kind)}
                          onChange={(e) => set('conversations', e.target.checked ? [...filters.conversations, kind] : filters.conversations.filter((x) => x !== kind))}
                        />
                        {label}
                      </label>
                    ))}
                  </fieldset>
                </>
              )}
              {scope === 'bookmarks' && (
                <div className={css.filters}>
                  <label className={css.check}>
                    <input type="checkbox" checked={filters.pinned} onChange={(e) => set('pinned', e.target.checked)} />
                    Pinned only
                  </label>
                  <label className={css.filter}>
                    Tag
                    <select className={css.filterInput} value={filters.tag} onChange={(e) => set('tag', e.target.value)}>
                      <option value="">Any</option>
                      {(tags.data ?? [])
                        .filter((t) => t.state === 'active')
                        .map((t) => (
                          <option key={t.slug} value={t.slug}>
                            {t.slug}
                          </option>
                        ))}
                    </select>
                  </label>
                  <label className={css.filter}>
                    Made
                    <select className={css.filterInput} value={filters.madeBy} onChange={(e) => set('madeBy', e.target.value as Filters['madeBy'])}>
                      <option value="">Either way</option>
                      <option value="resident">By {residentName}</option>
                      <option value="witness">From your suggestion</option>
                    </select>
                  </label>
                </div>
              )}
              {scope === 'scenes' && (
                <div className={css.filters}>
                  <label className={css.filter}>
                    Mood
                    <input className={css.filterInput} value={filters.mood} onChange={(e) => set('mood', e.target.value)} placeholder="glad" />
                  </label>
                  <label className={css.filter}>
                    Person
                    <input className={css.filterInput} value={filters.person} onChange={(e) => set('person', e.target.value)} placeholder="a name" />
                  </label>
                </div>
              )}
            </div>
          )}
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
          {scope === 'words' && searchable && (page > 1 || results.data?.more) && (
            <div className={css.pager}>
              <button type="button" className={css.scope} disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
                ‹ Newer page
              </button>
              <span className={css.note}>Page {page}</span>
              <button type="button" className={css.scope} disabled={!results.data?.more} onClick={() => setPage((p) => p + 1)}>
                Next page ›
              </button>
            </div>
          )}
        </Dialog>
      </Modal>
    </ModalOverlay>
  );
}

const KIND: Record<SearchResult['type'], string> = { transcript: 'Transcript', document: 'Record', bookmark: 'Bookmark', scene: 'Scene' };

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
