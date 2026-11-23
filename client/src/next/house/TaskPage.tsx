import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { QueueActivity, QueueEditEntry, QueueMove, QueueOverview, QueueTaskPage } from '../../api/types';
import { Confirm, Field, Said, Select, TextArea } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { HOUSE } from './keys';
import { actName, documentRows, drawLayers, forkNote, fromLine, GATED, glyph, LETS, nameOf, pin, rearranged, roleChoices, since, TYPES, type DrawnLayer, type Names } from './queueText';
import * as w from './work.css';
import { useWorkNav, workPath } from './workRoutes';

const QUEUE = [...HOUSE, 'queue'];

const useTaskPage = (number: number) => useQuery({ queryKey: [...QUEUE, 'task', number], queryFn: () => api.queueTask(number) });

/** A holder's chip: "you" in your colour, anyone else in theirs. */
export function Who({ assignee, names, me }: { assignee: string; names: Names; me: string }) {
  return <span className={assignee === me ? w.whoMe : w.who}>{nameOf(names, assignee)}</span>;
}

const stateWord = (view: string) => (view === 'done' ? 'done ✓' : view);

/**
 * The layers drawn (the queue mocks' Task page): each layer numbered on a
 * rail, the rail running down to the next with its arrow, the layer's
 * state beside its number, and its activities as boxes, each with its
 * glyph and type, its name, who holds it and its state. A box opens the
 * activity.
 */
export function LayersDrawn({ layers, names, me, onOpen, hold }: { layers: DrawnLayer[]; names: Names; me: string; onOpen: (id: string) => void; hold?: (a: DrawnLayer['acts'][number]) => string }) {
  return (
    <ol className={w.layers} aria-label="Layers">
      {layers.map((l, i) => (
        <li key={l.n} className={w.layer}>
          <div className={w.rail}>
            <span className={`${w.num} ${w.numState[l.state]}`}>{l.n}</span>
            {i < layers.length - 1 && (
              <>
                <span className={w.line} aria-hidden />
                <span className={w.arrow} aria-hidden>
                  ▼
                </span>
              </>
            )}
          </div>
          <div className={w.layerBody}>
            <span className={l.state === 'open' ? w.layerLabelOpen : w.layerLabel}>{l.label}</span>
            <div className={w.boxes}>
              {l.acts.map((a) => (
                <button key={a.id} type="button" className={w.box} data-state={a.view} onClick={() => onOpen(a.id)} aria-label={`${a.name}, ${a.type}, ${a.view}`}>
                  <span className={w.boxHead}>
                    <span>
                      {a.glyph} {a.type}
                      {a.slot ? ` · ${a.slot}` : ''}
                    </span>
                    {a.gated && <span className={w.gated}>gated</span>}
                  </span>
                  <span className={w.boxName}>{a.name}</span>
                  <span className={w.boxFoot}>
                    {hold ? <span className={w.meta}>{hold(a)}</span> : <Who assignee={a.assignee} names={names} me={me} />}
                    {a.view && <span className={w.stateWord[a.view as keyof typeof w.stateWord] ?? w.meta}>{stateWord(a.view)}</span>}
                  </span>
                </button>
              ))}
            </div>
          </div>
        </li>
      ))}
    </ol>
  );
}

/**
 * A task's page (the queue mocks' Task): its documents first (each with
 * its role, an empty slot "not yet", and Add a document), then its
 * layers drawn, where it came from, and New activity; what waits on it,
 * its history, and Drop.
 */
export function TaskPage({ number, names, overview }: { number: number; names: Names; overview: QueueOverview }) {
  const nav = useWorkNav();
  const page = useTaskPage(number);
  const act = useAct();
  const [note, setNote] = useState('');
  if (!page.data) return page.isError ? <p className={css.refused}>Task #{number} was not found.</p> : <p className={css.note}>Reading…</p>;
  const { task, layers, waiting, history }: QueueTaskPage = page.data;
  const mayEdit = task.status === 'open' && (task.owner === overview.me || overview.me.startsWith('witness:'));
  return (
    <>
      <button type="button" className={css.back} onClick={() => nav('')}>
        ‹ Work
      </button>
      <span className={w.meta}>
        #{task.number} · {task.project}
        {task.status !== 'open' ? ` · ${task.status}` : ''}
      </span>
      <h1 className={w.pageTitle}>{task.title}</h1>
      <p className={css.text}>{task.outcome}</p>
      <p className={css.meta}>
        Owner {nameOf(names, task.owner)} · {fromLine(task)}
      </p>
      <TaskDocuments number={task.number} documents={task.documents ?? []} mayEdit={task.status === 'open'} />
      <section className={css.card} aria-label="Layers">
        <div className={w.top}>
          <h2 className={css.heading}>Layers</h2>
          {mayEdit && (
            <button type="button" className={css.secondary} onClick={() => nav(workPath.newActivity(task.number))}>
              New activity
            </button>
          )}
        </div>
        <LayersDrawn layers={drawLayers(layers, task.open_layer)} names={names} me={overview.me} onOpen={(id) => nav(workPath.activity(task.number, id))} />
        {waiting.length > 0 && <p className={css.meta}>Waiting on this task: {waiting.map((a) => `${actName(a)} (#${a.task})`).join(', ')}</p>}
      </section>
      <details className={css.card}>
        <summary className={css.heading}>History · {history.length}</summary>
        <History rows={history} names={names} />
      </details>
      {mayEdit && (
        <div className={css.row}>
          <Field label="Why it is dropped" value={note} onChange={(e) => setNote(e.target.value)} />
          <Confirm label="Drop the task" confirm="Drop it? What waits on it is released." disabled={act.busy || !note.trim()} onConfirm={() => void act.run(() => api.queueDrop(task.number, note).then(() => `Task #${task.number} dropped.`), QUEUE)} />
        </div>
      )}
      <Said said={act.said} />
    </>
  );
}

function History({ rows, names }: { rows: QueueTaskPage['history']; names: Names }) {
  if (rows.length === 0) return <p className={css.note}>Nothing yet.</p>;
  return (
    <ul className={css.list}>
      {rows.map((h, i) => (
        <li key={i} className={css.meta} style={{ padding: '4px 0' }}>
          {new Date(h.at).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })} · {[h.act_id, h.what, h.outcome].filter(Boolean).join(' ')}
          {h.pin ? ` ${pin(h.pin)}` : ''} · {h.actor_id ? nameOf(names, `${h.actor_kind}:${h.actor_id}`) : h.actor_kind}
          {h.note ? `: ${h.note}` : ''}
        </li>
      ))}
    </ul>
  );
}

/** A task's documents (sunna#91): each opens the document screen; an attached one can go; a new one is added by citation with its role. */
function TaskDocuments({ number, documents, mayEdit }: { number: number; documents: NonNullable<QueueTaskPage['task']['documents']>; mayEdit: boolean }) {
  const nav = useWorkNav();
  const act = useAct();
  const [adding, setAdding] = useState(false);
  const [citation, setCitation] = useState('');
  const choices = roleChoices(documents);
  const [role, setRole] = useState('');
  const picked = choices.find((c) => c.role === role) ?? choices[0];
  const add = () =>
    void act.run(
      () =>
        (picked.fills ? api.queueFillSlot(number, picked.role, citation.trim()) : api.queueAttachDocument(number, citation.trim(), picked.role)).then(() => {
          setCitation('');
          setAdding(false);
          return `${citation.trim()} is on task #${number} as ${picked.fills ? `its ${picked.role}` : 'a source'}.`;
        }),
      QUEUE,
    );
  return (
    <section className={css.card} aria-label="Documents">
      <h2 className={css.heading}>Documents</h2>
      {documents.length === 0 && <p className={css.note}>No documents yet.</p>}
      <ul className={w.docs}>
        {documentRows(documents).map((d) => (
          <li key={d.key} className={w.docRow}>
            <div className={w.docMain}>
              {d.citation ? (
                <button type="button" className={css.linkButton} onClick={() => nav(workPath.doc(d.citation as string))}>
                  {d.citation}
                </button>
              ) : (
                <span className={w.docPath}>not yet: its activities fill it</span>
              )}
            </div>
            <span className={w.role}>{d.role}</span>
            {mayEdit && d.attached && d.citation && (
              <button type="button" className={css.quiet} aria-label={`Detach ${d.citation}`} disabled={act.busy} onClick={() => void act.run(() => api.queueDetachDocument(number, d.citation as string).then(() => `${d.citation} is off the task.`), QUEUE)}>
                ×
              </button>
            )}
          </li>
        ))}
      </ul>
      {mayEdit &&
        (adding ? (
          <div className={css.column}>
            <Field label="Its citation (lily:design/x.md, house/<house>:doc/<path>)" value={citation} onChange={(e) => setCitation(e.target.value)} />
            <Select label="As" value={picked.role} onChange={setRole}>
              {choices.map((c) => (
                <option key={c.role} value={c.role}>
                  {c.label}
                </option>
              ))}
            </Select>
            <div className={css.row}>
              <button type="button" className={css.primary} disabled={act.busy || !citation.trim()} onClick={add}>
                Add it
              </button>
              <button type="button" className={css.quiet} onClick={() => setAdding(false)}>
                Cancel
              </button>
            </div>
          </div>
        ) : (
          <div>
            <button type="button" className={css.quiet} onClick={() => setAdding(true)}>
              + Add a document
            </button>
          </div>
        ))}
      <Said said={act.said} />
    </section>
  );
}

/** Everyone an activity can be held by: the members, each resident's Claude Code, or not known yet. */
export function HolderOptions({ overview, names }: { overview: QueueOverview; names: Names }) {
  return (
    <>
      {overview.members.map((m) => (
        <option key={m.assignee} value={m.assignee}>
          {nameOf(names, m.assignee)}
        </option>
      ))}
      {overview.members
        .filter((m) => m.kind === 'resident')
        .map((m) => (
          <option key={`cc-${m.id}`} value={`claude-code:${m.id}`}>
            {m.name}'s Claude Code
          </option>
        ))}
      <option value="unknown">not known yet</option>
    </>
  );
}

type Fields = { type: string; assignee: string; artifact: string; destination: string; action: string; optional: boolean; throwback: string; layer: number };

const fieldsOf = (a: QueueActivity, layer: number): Fields => ({
  type: a.type,
  assignee: a.assignee,
  artifact: a.artifact ?? '',
  destination: a.destination ?? '',
  action: a.action ?? '',
  optional: a.optional,
  throwback: a.throwback ?? '',
  layer,
});

const blank = (open: number): Fields => ({ type: '', assignee: '', artifact: '', destination: '', action: '', optional: false, throwback: '', layer: open });

/**
 * One activity (the queue mocks' Activity): where it stands and the
 * moves it allows (a review held by you opens on its document: Review
 * it), then what it is, edited while it is pending and saved through the
 * task's layer edit (sunna#85) with the rest of the task as it stands.
 * Its name is the template's and is not changed here.
 */
export function ActivityPage({ number, actId, names, overview }: { number: number; actId: string; names: Names; overview: QueueOverview }) {
  const nav = useWorkNav();
  const page = useTaskPage(number);
  if (!page.data) return page.isError ? <p className={css.refused}>Task #{number} was not found.</p> : <p className={css.note}>Reading…</p>;
  const { task, layers, history } = page.data;
  const layer = layers.findIndex((l) => l.some((a) => a.act_id === actId));
  const a = layer >= 0 ? layers[layer].find((x) => x.act_id === actId) : undefined;
  if (!a) return <p className={css.refused}>Task #{number} has no activity {actId}.</p>;
  const live = a.view === 'ready' || a.view === 'active';
  const mine = a.assignee === overview.me;
  const mayEdit = task.status === 'open' && (task.owner === overview.me || overview.me.startsWith('witness:'));
  return (
    <>
      <button type="button" className={css.back} onClick={() => nav(workPath.task(number))}>
        ‹ {task.title}
      </button>
      <span className={w.meta}>
        {a.act_id} · layer {layer + 1}
      </span>
      <span className={w.typeWord}>
        {glyph(a.type)} {a.type}
      </span>
      <h1 className={w.pageTitle}>{actName(a)}</h1>
      <section className={css.card} aria-label="Where it stands">
        <p className={css.subheading}>
          {a.view === 'ready' && mine ? 'Ready for you' : `${a.view[0].toUpperCase()}${a.view.slice(1)}`}
          <span className={css.meta}> · {nameOf(names, a.assignee)}{a.ready_at && live ? ` · ready ${since(a.ready_at)} ago` : ''}</span>
        </p>
        {a.type === 'review' && a.artifact && !a.artifact.startsWith('slot:') && (
          <p className={css.note}>
            Approving authorizes {a.artifact}
            {pin(a.approved_pin ?? a.pin)}
            {a.action ? ` for ${a.action}` : ''}
            {a.destination ? ` to ${a.destination}` : ''}. If it changes after you approve, this opens again.
          </p>
        )}
        {(a.reason || a.note) && <p className={css.meta}>{a.reason ?? a.note}</p>}
        {a.type === 'review' && live && mine && a.artifact && !a.artifact.startsWith('slot:') && (
          <div>
            <button type="button" className={css.primary} onClick={() => nav(workPath.doc(a.artifact as string))}>
              Review it
            </button>
          </div>
        )}
        <Moves task={number} a={a} names={names} overview={overview} />
      </section>
      {mayEdit && <ActivityForm key={a.act_id} task={task} layers={layers} a={a} layer={layer} names={names} overview={overview} />}
      <section className={css.card} aria-label="History">
        <h2 className={css.heading}>History</h2>
        <History rows={history.filter((h) => h.act_id === a.act_id)} names={names} />
      </section>
    </>
  );
}

/**
 * An activity's fields, existing or new (the queue mocks' Activity and
 * Activity · new). A new one needs a name, and adding it forks the
 * template for this task (sunna#90), said before it is added.
 */
export function ActivityForm({ task, layers, a, layer, names, overview }: { task: QueueTaskPage['task']; layers: QueueActivity[][]; a: QueueActivity | null; layer: number; names: Names; overview: QueueOverview }) {
  const nav = useWorkNav();
  const act = useAct();
  const open = task.open_layer ?? layers.length;
  const [f, setF] = useState<Fields>(() => (a ? fieldsOf(a, layer) : blank(open)));
  const [name, setName] = useState('');
  const [other, setOther] = useState(false);
  const set = (patch: Partial<Fields>) => setF({ ...f, ...patch });
  const pending = !a || a.status === 'pending';
  const fork = forkNote(task);
  // Pending work moves between the open layer and later ones; started work stays where it is.
  const layerChoices = Array.from({ length: Math.max(layers.length - open, 0) + 1 }, (_, k) => open + k);
  const docs = (task.documents ?? []).map((d) => d.citation ?? d.key).filter((c, i, all) => all.indexOf(c) === i);
  const earlier = layers.slice(0, f.layer).flat().filter((x) => x.act_id !== a?.act_id);
  const review = f.type === 'review';
  const gatedType = GATED.includes(f.type);
  const entry = (): QueueEditEntry => {
    const fields = {
      type: f.type,
      assignee: f.assignee,
      artifact: f.artifact.trim() || null,
      destination: review || gatedType ? f.destination.trim() || null : null,
      action: review ? f.action || null : null,
      optional: f.optional,
      throwback: review ? f.throwback || null : null,
    };
    return a ? { id: a.act_id, ...fields } : { name: name.trim(), ...fields };
  };
  const save = (to: number | null, said: string, note: string) =>
    void act.run(
      () =>
        api.queueEditLayers(task.number, rearranged(layers, { id: a?.act_id ?? null, to, entry: to === null ? null : entry() }), note).then(() => {
          nav(workPath.task(task.number));
          return said;
        }),
      QUEUE,
    );
  const ready = !!f.type && !!f.assignee && (!!a || !!name.trim());
  return (
    <section className={css.card} aria-label="The activity">
      <h2 className={css.heading}>{a ? 'The activity' : 'New activity'}</h2>
      {!a && fork && <p className={w.warnNote}>{fork}</p>}
      {a ? (
        <div className={w.readOnly}>
          <span className={css.meta}>{task.template ? 'Named in the template' : 'Named for this task'}</span>
          <span>
            {actName(a)}
            {task.template && (
              <>
                {' '}
                <button type="button" className={css.linkButton} style={{ fontSize: 13 }} onClick={() => nav(`template/${task.template}`)}>
                  {task.template} ›
                </button>
              </>
            )}
          </span>
        </div>
      ) : (
        <>
          <Field label="Name" value={name} maxLength={80} onChange={(e) => setName(e.target.value)} placeholder="What everyone will call it" />
          <span className={css.meta}>The name belongs to the fork, the way a template's names belong to the template.</span>
        </>
      )}
      {!pending && <p className={css.note}>It has started, so what it is stays as it is.</p>}
      <fieldset disabled={!pending} style={{ border: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: 10, minWidth: 0 }}>
        <Select label="Type" value={f.type} onChange={(v) => set({ type: v })}>
          {!f.type && <option value="">Choose…</option>}
          {[...new Set([...TYPES, ...(f.type ? [f.type] : [])])].map((t) => (
            <option key={t} value={t}>
              {glyph(t)} {t}
            </option>
          ))}
        </Select>
        <Select label="Held by" value={f.assignee} onChange={(v) => set({ assignee: v })}>
          {!f.assignee && <option value="">Choose…</option>}
          <HolderOptions overview={overview} names={names} />
        </Select>
        <Select label="Layer" value={String(f.layer)} onChange={(v) => set({ layer: Number(v) })}>
          {pending ? (
            layerChoices.map((i) => (
              <option key={i} value={String(i)}>
                {i < layers.length ? `${i + 1}${i === open ? ' · open now' : ''}` : '+ a new layer'}
              </option>
            ))
          ) : (
            <option value={String(layer)}>{layer + 1}</option>
          )}
        </Select>
        {open > 0 && pending && <span className={css.meta}>Layer {open} is done, so nothing new goes before layer {open + 1}.</span>}
        {other ? (
          <Field label="Works on (a citation)" value={f.artifact} onChange={(e) => set({ artifact: e.target.value })} />
        ) : (
          <Select label={a ? 'Works on' : 'Works on (optional)'} value={f.artifact} onChange={(v) => (v === '__other' ? (setOther(true), set({ artifact: '' })) : set({ artifact: v }))}>
            <option value="">No document</option>
            {[...new Set([...docs, ...(f.artifact ? [f.artifact] : [])])].map((d) => (
              <option key={d} value={d}>
                {d.startsWith('slot:') ? `${d.slice(5)} (not yet filled)` : d}
              </option>
            ))}
            <option value="__other">Another document…</option>
          </Select>
        )}
        {review && (
          <Select label="Approving lets" value={f.action} onChange={(v) => set({ action: v })}>
            <option value="">nothing gated</option>
            {GATED.map((g) => (
              <option key={g} value={g}>
                {LETS[g] ?? g}
              </option>
            ))}
          </Select>
        )}
        {(review || gatedType) && <Field label="Destination (house, main, email…)" value={f.destination} onChange={(e) => set({ destination: e.target.value })} />}
        {review && (
          <Select label="If refused, back to" value={f.throwback} onChange={(v) => set({ throwback: v })}>
            <option value="">the reviewer picks</option>
            {earlier.map((x) => (
              <option key={x.act_id} value={x.act_id}>
                {layers.findIndex((l) => l.includes(x)) + 1} · {actName(x)}
              </option>
            ))}
          </Select>
        )}
        {!a && !f.type && <p className={css.note}>A review asks what approving lets happen and where a refusal sends the work; a send, publish, merge or promote asks for its review in the layer before. Those fields appear once a type is chosen.</p>}
        <label className={css.check}>
          <input type="checkbox" checked={f.optional} onChange={(e) => set({ optional: e.target.checked })} /> Optional: whoever holds it may skip it
        </label>
      </fieldset>
      <div className={css.row}>
        {a ? (
          <>
            <button type="button" className={css.primary} disabled={act.busy || !pending} onClick={() => save(f.layer, `${actName(a)} is saved.`, `Changed ${actName(a)} on the task page.`)}>
              Save changes
            </button>
            <button type="button" className={css.quiet} onClick={() => nav(workPath.task(task.number))}>
              Cancel
            </button>
            {pending && <Confirm label="Remove" confirm={fork && !task.forked ? 'Remove it? This forks the template for this task.' : 'Remove it?'} disabled={act.busy} onConfirm={() => save(null, `${actName(a)} is removed.`, `Removed ${actName(a)} on the task page.`)} />}
          </>
        ) : (
          <>
            <button type="button" className={css.primary} disabled={act.busy || !ready} onClick={() => save(f.layer, `${name.trim()} is added.`, `Added ${name.trim()} on the task page.`)}>
              Add the activity
            </button>
            <button type="button" className={css.quiet} onClick={() => nav(workPath.task(task.number))}>
              Cancel
            </button>
          </>
        )}
      </div>
      {!a && !ready && <span className={css.meta}>Adds once it has a name, a type and who holds it.</span>}
      <Said said={act.said} />
    </section>
  );
}

/** A new activity on a task (the queue mocks' Activity · new). */
export function NewActivityPage({ number, names, overview }: { number: number; names: Names; overview: QueueOverview }) {
  const nav = useWorkNav();
  const page = useTaskPage(number);
  if (!page.data) return page.isError ? <p className={css.refused}>Task #{number} was not found.</p> : <p className={css.note}>Reading…</p>;
  const { task, layers } = page.data;
  return (
    <>
      <button type="button" className={css.back} onClick={() => nav(workPath.task(number))}>
        ‹ {task.title}
      </button>
      <span className={w.meta}>#{task.number} · new activity</span>
      <h1 className={w.pageTitle}>New activity</h1>
      <ActivityForm task={task} layers={layers} a={null} layer={task.open_layer ?? layers.length} names={names} overview={overview} />
    </>
  );
}

/**
 * The moves an activity allows (sunna#80): take, finish, failed, block,
 * reopen, skip, assign; a review's decision is on its document's screen.
 */
function Moves({ task, a, names, overview }: { task: number; a: QueueActivity; names: Names; overview: QueueOverview }) {
  const act = useAct();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState('');
  const [waitsOn, setWaitsOn] = useState('');
  const [assignee, setAssignee] = useState(a.assignee);
  const move = (m: QueueMove, fields: Record<string, unknown> = {}, said = `${actName(a)}: ${m}.`) => void act.run(() => api.queueMove(task, a.act_id, m, fields).then(() => said), QUEUE);
  const live = a.view === 'ready' || a.view === 'active';
  const stuck = a.view === 'blocked' || a.view === 'failed';
  if (a.view === 'done' || a.view === 'skipped') return null;
  return (
    <>
      <div className={css.row}>
        {a.view === 'ready' && a.type !== 'review' && (
          <button type="button" className={css.primary} disabled={act.busy} onClick={() => move('take', {}, `${actName(a)} is yours, active.`)}>
            Take
          </button>
        )}
        <button type="button" className={css.secondary} aria-expanded={open} onClick={() => setOpen(!open)}>
          {open ? 'Fewer moves' : 'More moves'}
        </button>
      </div>
      {open && (
        <div className={css.column}>
          <TextArea label="Note, or the reason" value={note} onChange={(e) => setNote(e.target.value)} />
          {live && a.type !== 'review' && (
            <div className={css.row}>
              {a.type === 'promote-to-house' ? (
                <span className={css.note}>A promotion finishes when it is promoted.</span>
              ) : (
                <button type="button" className={css.primary} disabled={act.busy} onClick={() => move('finish', { note: note || undefined }, `${actName(a)} is done.`)}>
                  Finish
                </button>
              )}
              <button type="button" className={css.secondary} disabled={act.busy || !note.trim()} onClick={() => move('fail', { reason: note }, `${actName(a)} failed; it keeps its place.`)}>
                Failed
              </button>
            </div>
          )}
          {!stuck && (
            <div className={css.row}>
              <Select label="Waits on task" value={waitsOn} onChange={setWaitsOn}>
                <option value="">No task (a person clears it)</option>
                {overview.tasks
                  .filter((t) => t.number !== task && t.status === 'open')
                  .map((t) => (
                    <option key={t.number} value={String(t.number)}>
                      #{t.number} {t.title}
                    </option>
                  ))}
              </Select>
              <button type="button" className={css.secondary} disabled={act.busy || !note.trim()} onClick={() => move('block', { reason: note, waits_on: waitsOn ? Number(waitsOn) : null }, `${actName(a)} is blocked.`)}>
                Block
              </button>
            </div>
          )}
          {stuck && (
            <button type="button" className={css.secondary} disabled={act.busy || !note.trim()} onClick={() => move('reopen', { note }, `${actName(a)} is open again.`)}>
              Reopen
            </button>
          )}
          <div className={css.row}>
            <Confirm label="Skip" confirm="Skip it, with the note?" disabled={act.busy || !note.trim()} onConfirm={() => move('skip', { note }, `${actName(a)} skipped.`)} />
            <Select label="Assign to" value={assignee} onChange={setAssignee}>
              <HolderOptions overview={overview} names={names} />
            </Select>
            <button type="button" className={css.quiet} disabled={act.busy || assignee === a.assignee} onClick={() => move('assign', { assignee, note: note || undefined }, `${actName(a)} is ${nameOf(names, assignee)}'s.`)}>
              Assign
            </button>
          </div>
        </div>
      )}
      <Said said={act.said} />
    </>
  );
}

