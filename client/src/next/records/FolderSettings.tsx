import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import * as css from './records.css';

/**
 * A folder's settings (ui-structures.md D: kinds and routes live in the
 * record viewer): what the kind is, who edits it, whether it waits on the
 * witness, and how things arrive in it. Profiles and keys stay in
 * Settings. Changing what a kind is goes to her as a proposal.
 */
export function FolderSettings({ residentId, kind, onBack }: { residentId: string; kind: string; onBack: () => void }) {
  const kinds = useQuery({ queryKey: ['resident', residentId, 'records', 'kinds'], queryFn: () => api.kinds(residentId) });
  const routes = useQuery({ queryKey: ['resident', residentId, 'records', 'routes'], queryFn: () => api.routes(residentId) });

  const entry = kinds.data?.kinds.find((k) => k.kind === kind);
  const arriving = (routes.data?.routes ?? []).filter((r) => r.kind === kind);
  const open = (kinds.data?.proposals ?? []).filter((p) => p.kind === kind && p.agree === null);

  return (
    <ScrollArea label={`${kind} settings`}>
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ Records
        </button>
        <h1 className={css.title}>{entry?.label ?? kind}</h1>
        <div className={css.meta}>
          A KIND{entry?.created_by ? ` · DEFINED BY ${entry.created_by === 'resident' ? 'HER' : 'YOU'}` : ''}
          {entry?.folder ? ` · ${entry.folder}/` : ''}
        </div>

        <section className={css.card}>
          <h2 className={css.cardHeading}>WHAT IT IS</h2>
          {kinds.isPending && <p className={css.note}>Reading…</p>}
          {entry && (
            <div className={css.grid}>
              <span className={css.label}>Who edits</span>
              <span>{entry.own ? 'Hers' : 'Either of you'}</span>
              <span className={css.label}>Waits on you</span>
              <span>{entry.approvable ? (entry.gated ? 'Yes, before it lands' : 'Can be asked to') : 'No'}</span>
              <span className={css.label}>May cite</span>
              <span>{entry.cites ? 'Yes' : 'No'}</span>
            </div>
          )}
          {open.map((p) => (
            <p key={p.number} className={css.note}>
              Open proposal #{p.number} from {p.proposed_by === 'resident' ? 'her' : 'you'}: {p.approvable ? 'make it wait on you' : 'stop waiting on you'}
              {p.note ? ` — "${p.note}"` : ''}
            </p>
          ))}
        </section>

        <section className={css.card}>
          <h2 className={css.cardHeading}>HOW THINGS ARRIVE</h2>
          {arriving.length === 0 && <p className={css.note}>She writes these herself; no route brings anything in.</p>}
          {arriving.map((r) => (
            <div key={r.key} className={css.grid}>
              <span className={css.label}>{r.label}</span>
              <span style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 12 }}>
                {r.direction} · {r.cadence} · profile {r.profile}
              </span>
            </div>
          ))}
          <p className={css.note}>Profiles and their keys live in Settings.</p>
        </section>
      </div>
    </ScrollArea>
  );
}
