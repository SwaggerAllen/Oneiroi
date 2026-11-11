import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { NoteAction, PageHead } from './NoteAction';
import { day, pluginActions } from './soul';
import * as css from './soul.css';

/**
 * Plugins (brain#68, agathos-daimon#37), ported from the current client's
 * Agreement › Plugins: what her context is assembled from. A memory slot
 * moves only when one of you proposes and the other agrees; an
 * installable plugin switches off at either word. Every change carries a
 * note.
 */
export function Plugins({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const data = useQuery({ queryKey: ['resident', id, 'soul', 'plugins'], queryFn: () => api.plugins(id) });
  const proposals = data.data?.proposals ?? [];
  const open = proposals.filter((p) => p.answered_at === null);
  const answered = proposals.filter((p) => p.answered_at !== null).slice(0, 5);
  const waiting = new Set(open.map((p) => p.key));
  const area = ['soul', 'plugins'];

  return (
    <ScrollArea label="Plugins">
      <div className={css.page}>
        <PageHead
          title="Plugins"
          lead={`What ${name}'s context is assembled from. A memory slot changes only when one of you proposes and the other agrees; an installable plugin switches off at either word.`}
          onBack={onBack}
        />
        {data.isPending && <p className={css.note}>Reading…</p>}
        {open.length > 0 && <h2 className={css.headingWitness}>OPEN PROPOSALS</h2>}
        {open.map((p) => (
          <div key={p.number} className={css.cardWaiting}>
            <p className={css.meta}>
              #{p.number} · {p.change.toUpperCase()} {p.key} · PROPOSED BY {p.proposed_by === 'resident' ? name.toUpperCase() : 'YOU'} {day(p.proposed_at)}
            </p>
            {p.note && <p className={p.proposed_by === 'resident' ? css.words : css.plain}>“{p.note}”</p>}
            {p.proposed_by === 'resident' ? (
              <div className={css.buttons}>
                <NoteAction label="Agree" primary confirm="Agree with this note" placeholder={`For ${name} to read`} run={(note) => api.answerPlugin(id, p.number, true, note)} area={area} />
                <NoteAction label="Decline" confirm="Decline with this note" placeholder={`Why, for ${name} to read`} run={(note) => api.answerPlugin(id, p.number, false, note)} area={area} />
              </div>
            ) : (
              <p className={css.note}>Waiting on {name}.</p>
            )}
          </div>
        ))}
        <h2 className={css.heading}>EVERY PLUGIN</h2>
        {(data.data?.plugins ?? []).map((p) => (
          <div key={p.key} className={css.card}>
            <p className={css.meta}>
              {p.key} · {p.on ? 'ON' : p.installed ? 'INSTALLED, OFF' : 'NOT INSTALLED'}
              {p.carried_over ? ' · CARRIED OVER FROM BEFORE PLUGINS' : ''}
            </p>
            <p className={css.plain}>
              <strong>{p.name}</strong> — {p.about}
              {p.author ? ` · by ${p.author}` : ''}
            </p>
            {p.audit && (
              <p className={css.note}>
                {p.audit.pinned === null ? 'Its lockfile is missing.' : p.audit.verified ? `Its ${p.audit.files} files match what was installed.` : 'Its files no longer match what was installed.'}
                {p.audit.update ? ' The catalog holds a newer version; taking it is a removal and an install, both of you.' : ''}
                {p.audit.shown > 0 ? ` In ${name}'s context on ${p.audit.shown} turns.` : ` Not yet in ${name}'s context.`}
              </p>
            )}
            {waiting.has(p.key) ? (
              <p className={css.note}>A proposal is open.</p>
            ) : (
              <div className={css.buttons}>
                {pluginActions(p, false).map((a) =>
                  a.kind === 'off' ? (
                    <NoteAction key="off" label={a.label} confirm="Switch off with this note" placeholder={`Why, for ${name} to read`} run={(note) => api.pluginOff(id, p.key, note)} area={area} />
                  ) : (
                    <NoteAction key={a.change} label={a.label} confirm="Propose with this note" placeholder={`Why, for ${name} to read`} run={(note) => api.proposePlugin(id, p.key, a.change, note)} area={area} />
                  ),
                )}
              </div>
            )}
          </div>
        ))}
        {answered.length > 0 && <h2 className={css.heading}>LATELY ANSWERED</h2>}
        {answered.map((p) => (
          <p key={p.number} className={css.note}>
            #{p.number} {p.change} {p.key}: {p.agreed ? 'agreed' : 'declined'}
            {p.answer_note ? `, “${p.answer_note}”` : ''}
          </p>
        ))}
      </div>
    </ScrollArea>
  );
}
