import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type ContractVersion } from '../../api/client';
import { Markdown } from '../chat/Markdown';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './soul.css';

const IDENTITY = ['SOUL.md', 'IDENTITY.md', 'USER.md', 'GOALS.md', 'LINKS.md'];

/**
 * Soul (ui-structures.md D): everything that rides every turn. The
 * agreement first, with the cyan glow and its decision when one waits on
 * the witness; then the identity files, her pins, the reacts vocabulary,
 * the plugins and the model.
 */
export function SoulTab() {
  const { id, name } = useSubject();
  const agreement = useQuery({ queryKey: ['resident', id, 'soul', 'agreement'], queryFn: () => api.agreement(id) });
  const files = useQuery({ queryKey: ['resident', id, 'soul', 'files'], queryFn: () => api.files(id) });
  const bookmarks = useQuery({ queryKey: ['resident', id, 'memory', 'bookmarks'], queryFn: () => api.bookmarks(id) });
  const vocabulary = useQuery({ queryKey: ['resident', id, 'soul', 'reacts-vocabulary'], queryFn: () => api.reactVocabulary(id) });
  const plugins = useQuery({ queryKey: ['resident', id, 'soul', 'plugins'], queryFn: () => api.plugins(id) });
  const residents = useQuery({ queryKey: ['residents'], queryFn: api.residents });
  const [openFile, setOpenFile] = useState<string | null>(null);

  const contract = agreement.data?.contract;
  const pins = (bookmarks.data ?? []).filter((b) => b.pinned_at).sort((a, b) => a.number - b.number);
  const model = residents.data?.find((r) => r.id === id)?.chat_model;
  const filesByName = new Map((files.data ?? []).map((f) => [f.name, f.content]));

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
        </section>

        <section className={css.section}>
          <h2 className={css.heading}>WHO SHE IS</h2>
          {IDENTITY.filter((f) => filesByName.has(f)).map((f) => (
            <div key={f} className={css.file}>
              <button type="button" className={css.fileHead} aria-expanded={openFile === f} onClick={() => setOpenFile(openFile === f ? null : f)}>
                <span>{f}</span>
                <span className={css.meta}>{openFile === f ? 'CLOSE' : 'READ'}</span>
              </button>
              {openFile === f && (
                <div className={css.fileBody}>
                  <Markdown text={filesByName.get(f) ?? ''} onCite={() => undefined} />
                </div>
              )}
            </div>
          ))}
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
