import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type ContractVersion } from '../../api/client';
import { Markdown } from '../chat/Markdown';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { AgreementPage } from './AgreementPage';
import { Proposals, Revisions, Tags } from './Between';
import { Commitments, Habits, Letters, Positions, Predictions, Seeds, SoulLines } from './Character';
import { FileEdit } from './FileEdit';
import { NoteAction } from './NoteAction';
import { Plugins } from './Plugins';
import { IDENTITY, proposedTags, soulPage } from './soul';
import * as css from './soul.css';

/**
 * Soul (ui-structures.md D): everything that rides every turn. The
 * agreement first, with the cyan glow and its decision when one waits on
 * the witness; then the identity files with your edit proposals, her
 * pins, her character, what passes between you about her memory, the
 * reacts vocabulary, the plugins and the model. The stack's top names a
 * page (`agreement`, `edit/SOUL.md`, `habits`, …; soul.ts).
 */
export function SoulTab({ path }: { path: string }) {
  const back = useShell((s) => s.back);
  const at = soulPage(path);
  switch (at.page) {
    case 'root':
      return <Root />;
    case 'edit':
      return <FileEdit file={at.file} onDone={back} />;
    case 'agreement':
      return <AgreementPage onBack={back} />;
    case 'plugins':
      return <Plugins onBack={back} />;
    case 'soul-lines':
      return <SoulLines onBack={back} />;
    case 'habits':
      return <Habits onBack={back} />;
    case 'seeds':
      return <Seeds onBack={back} />;
    case 'commitments':
      return <Commitments onBack={back} />;
    case 'positions':
      return <Positions onBack={back} />;
    case 'predictions':
      return <Predictions onBack={back} />;
    case 'letters':
      return <Letters onBack={back} />;
    case 'tags':
      return <Tags onBack={back} />;
    case 'revisions':
      return <Revisions onBack={back} />;
    case 'proposals':
      return <Proposals onBack={back} />;
  }
}

function Root() {
  const { id, name } = useSubject();
  const push = useShell((s) => s.push);
  const agreement = useQuery({ queryKey: ['resident', id, 'soul', 'agreement'], queryFn: () => api.agreement(id) });
  const files = useQuery({ queryKey: ['resident', id, 'soul', 'files'], queryFn: () => api.files(id) });
  const bookmarks = useQuery({ queryKey: ['resident', id, 'memory', 'bookmarks'], queryFn: () => api.bookmarks(id) });
  const vocabulary = useQuery({ queryKey: ['resident', id, 'soul', 'reacts-vocabulary'], queryFn: () => api.reactVocabulary(id) });
  const plugins = useQuery({ queryKey: ['resident', id, 'soul', 'plugins'], queryFn: () => api.plugins(id) });
  const residents = useQuery({ queryKey: ['residents'], queryFn: api.residents });
  // What waits, for the rows' counts.
  const edits = useQuery({ queryKey: ['resident', id, 'soul', 'soul-edits'], queryFn: () => api.soulEdits(id) });
  const bookmarkProposals = useQuery({ queryKey: ['resident', id, 'soul', 'bookmark-proposals'], queryFn: () => api.bookmarkProposals(id) });
  const tags = useQuery({ queryKey: ['resident', id, 'soul', 'tags'], queryFn: () => api.tags(id) });
  const revisions = useQuery({ queryKey: ['resident', id, 'soul', 'revisions'], queryFn: () => api.revisions(id) });
  const predictions = useQuery({ queryKey: ['resident', id, 'soul', 'predictions'], queryFn: () => api.predictions(id) });
  const commitments = useQuery({ queryKey: ['resident', id, 'soul', 'commitments'], queryFn: () => api.commitments(id) });
  const [openFile, setOpenFile] = useState<string | null>(null);

  const contract = agreement.data?.contract;
  const pins = (bookmarks.data ?? []).filter((b) => b.pinned_at).sort((a, b) => a.number - b.number);
  const model = residents.data?.find((r) => r.id === id)?.chat_model;
  const filesByName = new Map((files.data ?? []).map((f) => [f.name, f.content]));
  const editsWaiting = new Set((edits.data ?? []).map((e) => e.file));
  const yoursOpen = (edits.data?.length ?? 0) + (bookmarkProposals.data?.length ?? 0);
  const tagsWaiting = proposedTags(tags.data ?? []).length;
  const stancesOpen = (revisions.data ?? []).filter((r) => r.state === 'proposed').length;
  const toResolve = predictions.data?.open.length ?? 0;
  const promised = (commitments.data ?? []).filter((c) => c.state === 'open').length;
  const pluginsWaiting = (plugins.data?.proposals ?? []).filter((p) => p.answered_at === null && p.proposed_by === 'resident').length;

  const row = (label: string, page: string, count?: string, waiting = false) => (
    <button key={page} type="button" className={css.link} onClick={() => push(page)}>
      <span>{label}</span>
      <span className={waiting ? css.waits : css.meta}>{count ? `${count} ›` : '›'}</span>
    </button>
  );

  return (
    <ScrollArea label="Soul">
      <div className={css.page}>
        <section className={css.agreement} aria-label="Your agreement">
          <h2 className={css.headingWitness}>YOUR AGREEMENT WITH {name.toUpperCase()}</h2>
          {agreement.isPending && <p className={css.note}>Reading…</p>}
          {contract?.open && <OpenVersion v={contract.open} name={name} inForce={contract.in_force} />}
          {contract?.in_force && !contract.open && <VersionBody v={contract.in_force} />}
          {!contract?.in_force && !contract?.open && agreement.data && (
            <p className={css.note}>Unstated: no version has been agreed yet.</p>
          )}
          {contract?.in_force && (
            <p className={css.meta}>
              VERSION {contract.in_force.version} IN FORCE SINCE {contract.since ? new Date(contract.since).toLocaleDateString() : '—'}
              {contract.due ? ' · RENEWAL DUE' : ''}
            </p>
          )}
          {contract?.in_force && contract.due && (
            <NoteAction
              label={`Renew version ${contract.in_force.version}`}
              confirm="Renew with this note"
              placeholder={`It has stood a year. A note for ${name}.`}
              run={(note) => api.renewContract(id, contract.in_force?.version ?? 0, note)}
              area={['soul', 'agreement']}
            />
          )}
          {row('Switches, versions, and who looks after her', 'agreement')}
        </section>

        <section className={css.section}>
          <h2 className={css.heading}>WHO SHE IS</h2>
          {IDENTITY.map((f) => (
            <div key={f} className={css.file}>
              <button type="button" className={css.fileHead} aria-expanded={openFile === f} onClick={() => setOpenFile(openFile === f ? null : f)}>
                <span>{f}</span>
                <span className={editsWaiting.has(f) ? css.waits : css.meta}>{editsWaiting.has(f) ? 'YOUR EDIT WAITS ON HER · ' : ''}
                  {filesByName.has(f) ? '' : 'NOT WRITTEN · '}
                  {openFile === f ? 'CLOSE' : 'OPEN'}</span>
              </button>
              {openFile === f && (
                <div className={css.fileBody}>
                  {filesByName.has(f) ? <Markdown text={filesByName.get(f) ?? ''} onCite={() => undefined} /> : <p className={css.note}>Not written yet.</p>}
                  <div className={css.buttons}>
                    <button type="button" className={css.small} onClick={() => push(`edit/${f}`)}>
                      Propose an edit
                    </button>
                  </div>
                </div>
              )}
            </div>
          ))}
          {row('Soul lines', 'soul-lines')}
        </section>

        <section className={css.section}>
          <h2 className={css.heading}>HER PINS</h2>
          {pins.length === 0 && <p className={css.note}>Nothing pinned yet.</p>}
          {pins.map((b) => (
            <div key={b.number} className={css.pin}>
              <span className={css.pinNumber}>#{b.number}</span>
              <span>{b.line}</span>
            </div>
          ))}
        </section>

        <section className={css.section}>
          <h2 className={css.heading}>HER CHARACTER</h2>
          {row('Habits', 'habits')}
          {row('Seeds', 'seeds')}
          {row('Commitments', 'commitments', promised ? `${promised} OPEN` : undefined)}
          {row('Positions', 'positions')}
          {row('Predictions', 'predictions', toResolve ? `${toResolve} TO RESOLVE` : undefined, toResolve > 0)}
          {row('Letters to her next self', 'letters')}
        </section>

        <section className={css.section}>
          <h2 className={css.heading}>BETWEEN YOU</h2>
          {row('Tags', 'tags', tagsWaiting ? `${tagsWaiting} WAIT ON YOU` : undefined, tagsWaiting > 0)}
          {row('Revisions', 'revisions', stancesOpen ? `${stancesOpen} WITH HER` : undefined)}
          {row('Your proposals', 'proposals', yoursOpen ? `${yoursOpen} WITH HER` : undefined)}
        </section>

        <section className={css.section}>
          <h2 className={css.heading}>REACTS · WHAT EACH MEANS</h2>
          <div className={css.vocabulary}>
            {(vocabulary.data ?? []).map((v) => (
              <span key={v.emoji} className={css.word}>
                {v.emoji} {v.meaning}
              </span>
            ))}
          </div>
        </section>

        <section className={css.section}>
          <h2 className={css.heading}>PLUGINS · MODEL</h2>
          {(plugins.data?.plugins ?? []).filter((p) => p.installed).map((p) => (
            <div key={p.key} className={css.row}>
              <span>{p.name}</span>
              <span className={css.meta}>{p.on ? 'ON' : 'OFF'}</span>
            </div>
          ))}
          {row('Every plugin, and proposals', 'plugins', pluginsWaiting ? `${pluginsWaiting} WAIT ON YOU` : undefined, pluginsWaiting > 0)}
          <div className={css.row}>
            <span>Model</span>
            <span className={css.meta}>{model ?? 'the platform default'}</span>
          </div>
        </section>
      </div>
    </ScrollArea>
  );
}

function VersionBody({ v }: { v: ContractVersion }) {
  const enforced = Object.entries(v.terms).filter(([, on]) => on);
  return (
    <>
      {enforced.length > 0 && (
        <div className={css.terms}>
          {enforced.map(([key]) => (
            <span key={key} className={css.term}>
              ENFORCED · {key.replace(/_/g, ' ')}
            </span>
          ))}
        </div>
      )}
      <div className={css.prose}>
        <Markdown text={v.prose} onCite={() => undefined} />
      </div>
    </>
  );
}

function OpenVersion({ v, name, inForce }: { v: ContractVersion; name: string; inForce: ContractVersion | null }) {
  const { id } = useSubject();
  const queries = useQueryClient();
  const [mode, setMode] = useState<'read' | 'decline' | 'amend'>('read');
  const [note, setNote] = useState('');
  const [prose, setProse] = useState(v.prose);
  const done = () => queries.invalidateQueries({ queryKey: ['resident', id, 'soul', 'agreement'] });
  const decide = useMutation({
    mutationFn: (d: 'agree' | 'decline') => api.decideContract(id, v.version, d, note),
    onSuccess: done,
  });
  const amend = useMutation({ mutationFn: () => api.proposeContract(id, v.terms, prose, note), onSuccess: done });
  const waitsOnWitness = v.proposed_by === 'resident';

  return (
    <>
      <p className={css.meta}>
        V{v.version} · PROPOSED BY {v.proposed_by === 'resident' ? name.toUpperCase() : 'YOU'} ·{' '}
        {new Date(v.proposed_at).toLocaleDateString()}
        {waitsOnWitness ? ' · WAITING ON YOU' : ` · WAITING ON ${name.toUpperCase()}`}
        {inForce ? ` · V${inForce.version} STAYS IN FORCE MEANWHILE` : ''}
      </p>
      {mode === 'amend' ? (
        <textarea className={css.editor} value={prose} onChange={(e) => setProse(e.target.value)} aria-label="Amended agreement" rows={14} />
      ) : (
        <VersionBody v={v} />
      )}
      {v.note && (
        <p className={css.note}>
          {v.proposed_by === 'resident' ? `${name}'s note` : 'Your note'}: “{v.note}”
        </p>
      )}
      {waitsOnWitness && (
        <div className={css.decision}>
          {mode !== 'read' && (
            <textarea
              className={css.noteBox}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder={mode === 'decline' ? 'Why, for her to read' : 'What you changed, and why'}
              aria-label="Note"
              rows={2}
            />
          )}
          <div className={css.buttons}>
            {mode === 'read' && (
              <>
                <button type="button" className={css.primary} disabled={decide.isPending} onClick={() => decide.mutate('agree')}>
                  Agree
                </button>
                <button type="button" className={css.secondary} onClick={() => setMode('amend')}>
                  Amend
                </button>
                <button type="button" className={css.secondary} onClick={() => setMode('decline')}>
                  Decline
                </button>
              </>
            )}
            {mode === 'decline' && (
              <button type="button" className={css.secondary} disabled={!note.trim() || decide.isPending} onClick={() => decide.mutate('decline')}>
                Decline with this note
              </button>
            )}
            {mode === 'amend' && (
              <button type="button" className={css.primary} disabled={!note.trim() || amend.isPending} onClick={() => amend.mutate()}>
                Propose this version to {name}
              </button>
            )}
            {mode !== 'read' && (
              <button type="button" className={css.secondary} onClick={() => setMode('read')}>
                Cancel
              </button>
            )}
          </div>
          {(decide.error || amend.error) && <p className={css.note}>{((decide.error ?? amend.error) as Error).message}</p>}
        </div>
      )}
    </>
  );
}
