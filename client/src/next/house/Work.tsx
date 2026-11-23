import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { useLive } from '../live/context';
import { api } from '../../api/client';
import type { QueueActivity, QueueCard, QueueMove, QueueOverview, QueueTaskPage, QueueView } from '../../api/types';
import { Card, Confirm, Field, Said, Select, TextArea } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { HOUSE } from './keys';
import { blockerLine, nameOf, pin, sentence, slugify, type Names } from './queueText';

/** The house queue's query keys: under the house's root, so a house write reads them again too. */
const QUEUE = [...HOUSE, 'queue'];

const VIEWS: QueueView[] = ['ready', 'active', 'waiting', 'blocked', 'failed'];





/**
 * Work (screen:next-work, sunna#80, lily:design/queue-ia rev 5 §2): the
 * house queue, one screen at different filters. It opens on Waiting on
 * me; Who, Status and Project change the view. A card reads as a
 * sentence, and a blocked card names its blocker, that task's next
 * action and whose it is, on its second line (Scarlett's guard).
 */
export function HouseWork() {
  const overview = useQuery({ queryKey: QUEUE, queryFn: api.queue });
  // Driven by the household's notices, never a timer (sunna#80).
  const live = useLive();
  const householdId = overview.data?.household_id;
  useEffect(() => (live && householdId ? live.house(householdId) : undefined), [live, householdId]);
  const [who, setWho] = useState('');
  const [view, setView] = useState<QueueView | ''>('');
  const [project, setProject] = useState('');
  const [taskOpen, setTaskOpen] = useState<number | null>(null);

  if (overview.isPending) return <p className={css.note}>Reading…</p>;
  if (!overview.data) return <p className={css.refused}>The house queue could not be read.</p>;
  const q = overview.data;
  // The viewer's own are "you": the house's name for a witness is long.
  const names: Names = { ...Object.fromEntries(q.members.map((m) => [m.assignee, m.name])), [q.me]: 'you' };
  const me = who || q.me;
  const mine = me === q.me && !view && !project;

  return (
    <>
      {!q.cut_over && (
        <p className={css.note}>
          The house queue is not on yet: the old work queues still run. Build the templates and move the work in progress, then turn it on below.
        </p>
      )}
      <div className={css.chips} role="group" aria-label="Filters">
        <Select label="Who" value={who} onChange={setWho}>
          <option value="">Me</option>
          <option value="anyone">Anyone</option>
          {q.members
            .filter((m) => m.assignee !== q.me)
            .map((m) => (
              <option key={m.assignee} value={m.assignee}>
                {m.name}
              </option>
            ))}
          <option value="claude-code">Claude Code</option>
          <option value="unknown">Holder not known yet</option>
        </Select>
        <Select label="Status" value={view} onChange={(v) => setView(v as QueueView | '')}>
          <option value="">Any</option>
          {VIEWS.map((v) => (
            <option key={v} value={v}>
              {v}
            </option>
          ))}
        </Select>
        <Select label="Project" value={project} onChange={setProject}>
          <option value="">All</option>
          {q.projects.map((p) => (
            <option key={p.slug} value={p.slug}>
              {p.name}
            </option>
          ))}
        </Select>
      </div>
      {mine ? <WaitingOnMe names={names} overview={q} onTask={setTaskOpen} /> : <Filtered who={me} view={view} project={project} names={names} overview={q} onTask={setTaskOpen} />}
      {taskOpen !== null && <TaskPanel number={taskOpen} names={names} overview={q} onClose={() => setTaskOpen(null)} />}
      <NewTask overview={q} />
      <Setup overview={q} names={names} />
    </>
  );
}

function WaitingOnMe({ names, overview, onTask }: { names: Names; overview: QueueOverview; onTask: (n: number) => void }) {
  const waiting = useQuery({ queryKey: [...QUEUE, 'waiting'], queryFn: () => api.queueWaiting() });
  if (!waiting.data) return <p className={css.note}>Reading…</p>;
  const w = waiting.data;
  return (
    <>
      <Card title={`Waiting on you · ${w.ready.length}`}>
        {w.ready.length === 0 && <p className={css.note}>Nothing waits on you.</p>}
        {w.ready.map((c) => (
          <ActivityCard key={c.act} card={c} names={names} overview={overview} onTask={onTask} />
        ))}
      </Card>
      <details className={css.card}>
        <summary className={css.heading}>Yours in a later layer, or blocked · {w.later.length}</summary>
        {w.later.map((c) => (
          <ActivityCard key={c.act} card={c} names={names} overview={overview} onTask={onTask} />
        ))}
      </details>
      <details className={css.card}>
        <summary className={css.heading}>Tasks you own · {w.owned.length}</summary>
        {w.owned.map(({ task, next }) => (
          <button key={task.number} type="button" className={css.linkButton} onClick={() => onTask(task.number)}>
            #{task.number} {task.title} · {task.project} · next: {next ? `${next.type}, ${nameOf(names, next.assignee)} (${next.view})` : 'nothing open'}
          </button>
        ))}
      </details>
    </>
  );
}

function Filtered({ who, view, project, names, overview, onTask }: { who: string; view: QueueView | ''; project: string; names: Names; overview: QueueOverview; onTask: (n: number) => void }) {
  const cards = useQuery({
    queryKey: [...QUEUE, 'activities', who, view, project],
    queryFn: () => api.queueActivities({ who, view: view ? [view] : [], project: project || undefined }),
  });
  if (!cards.data) return <p className={css.note}>Reading…</p>;
  return (
    <Card title={`Activities · ${cards.data.length}`}>
      {cards.data.length === 0 && <p className={css.note}>Nothing matches.</p>}
      {cards.data.map((c) => (
        <ActivityCard key={c.act} card={c} names={names} overview={overview} onTask={onTask} />
      ))}
    </Card>
  );
}



function ActivityCard({ card: c, names, overview, onTask }: { card: QueueCard; names: Names; overview: QueueOverview; onTask: (n: number) => void }) {
  const act = useAct();
  const [open, setOpen] = useState(false);
  const blocked = blockerLine(c, names);
  const move = (m: QueueMove, fields: Record<string, unknown> = {}, said = `${c.act}: ${m}.`) =>
    void act.run(() => api.queueMove(c.task, c.act, m, fields).then(() => said), QUEUE);
  const live = c.view === 'ready' || c.view === 'active';
  return (
    <div className={css.item}>
      <button type="button" className={css.linkButton} onClick={() => setOpen(!open)} aria-expanded={open}>
        {sentence(c, names)}
      </button>
      {blocked && <span className={css.warn}>{blocked}</span>}
      {c.note && <span className={css.meta}>{c.note}</span>}
      <div className={css.row}>
        {c.type === 'review' && live ? (
          <button type="button" className={css.primary} onClick={() => setOpen(true)}>
            Review
          </button>
        ) : c.view === 'ready' ? (
          <button type="button" className={css.primary} disabled={act.busy} onClick={() => move('take', {}, `${c.act} is yours, active.`)}>
            Take
          </button>
        ) : null}
        <button type="button" className={css.quiet} onClick={() => onTask(c.task)}>
          Task #{c.task} ›
        </button>
      </div>
      {open && (c.type === 'review' && live ? <Decide card={c} onDone={() => setOpen(false)} /> : <Moves card={c} names={names} overview={overview} move={move} busy={act.busy} />)}
      <Said said={act.said} />
    </div>
  );
}

function Moves({ card: c, names, overview, move, busy }: { card: QueueCard; names: Names; overview: QueueOverview; move: (m: QueueMove, f?: Record<string, unknown>, said?: string) => void; busy: boolean }) {
  const [note, setNote] = useState('');
  const [waitsOn, setWaitsOn] = useState('');
  const [assignee, setAssignee] = useState(c.assignee);
  const live = c.view === 'ready' || c.view === 'active';
  const stuck = c.view === 'blocked' || c.view === 'failed';
  const finished = c.view === 'done' || c.view === 'skipped';
  if (finished) return <p className={css.note}>{c.view}.</p>;
  return (
    <div className={css.column}>
      <TextArea label="Note, or the reason" value={note} onChange={(e) => setNote(e.target.value)} />
      {live && (
        <div className={css.row}>
          {c.type === 'promote-to-house' ? (
            <span className={css.note}>A promotion finishes when it is promoted (household_promote with this task and activity).</span>
          ) : (
            <button type="button" className={css.primary} disabled={busy} onClick={() => move('finish', { note: note || undefined }, `${c.act} is done.`)}>
              Finish
            </button>
          )}
          <button type="button" className={css.secondary} disabled={busy || !note.trim()} onClick={() => move('fail', { reason: note }, `${c.act} failed; it keeps its place.`)}>
            Failed
          </button>
        </div>
      )}
      {!stuck && (
        <div className={css.row}>
          <Select label="Waits on task" value={waitsOn} onChange={setWaitsOn}>
            <option value="">No task (a person clears it)</option>
            {overview.tasks
              .filter((t) => t.number !== c.task && t.status === 'open')
              .map((t) => (
                <option key={t.number} value={String(t.number)}>
                  #{t.number} {t.title}
                </option>
              ))}
          </Select>
          <button type="button" className={css.secondary} disabled={busy || !note.trim()} onClick={() => move('block', { reason: note, waits_on: waitsOn ? Number(waitsOn) : null }, `${c.act} is blocked.`)}>
            Block
          </button>
        </div>
      )}
      {stuck && (
        <button type="button" className={css.secondary} disabled={busy || !note.trim()} onClick={() => move('reopen', { note }, `${c.act} is open again.`)}>
          Reopen
        </button>
      )}
      <div className={css.row}>
        <Confirm label="Skip" confirm="Skip it, with the note?" disabled={busy || !note.trim()} onConfirm={() => move('skip', { note }, `${c.act} skipped.`)} />
        <Select label="Assign to" value={assignee} onChange={setAssignee}>
          {overview.members.map((m) => (
            <option key={m.assignee} value={m.assignee}>
              {m.name}
            </option>
          ))}
          <option value="claude-code">Claude Code</option>
          <option value="unknown">Holder not known yet</option>
        </Select>
        <button type="button" className={css.quiet} disabled={busy || assignee === c.assignee} onClick={() => move('assign', { assignee, note: note || undefined }, `${c.act} is ${nameOf(names, assignee)}'s.`)}>
          Assign
        </button>
      </div>
    </div>
  );
}

/**
 * A review's decision (§7): approval authorizes this revision, this
 * destination, this action, and nothing else; a refusal carries a note
 * and the activity the work goes back to.
 */
function Decide({ card: c, onDone }: { card: QueueCard; onDone: () => void }) {
  const act = useAct();
  const page = useQuery({ queryKey: [...QUEUE, 'task', c.task], queryFn: () => api.queueTask(c.task) });
  const [note, setNote] = useState('');
  const [returnTo, setReturnTo] = useState('');
  const [withhold, setWithhold] = useState(false);
  const earlier = (page.data?.layers ?? []).slice(0, c.layer).flat();
  const decide = (outcome: 'approved' | 'changes' | 'declined') =>
    void act.run(
      () =>
        api
          .queueMove(c.task, c.act, 'decide', { outcome, note, return_to: outcome === 'approved' ? undefined : returnTo || undefined, withhold: outcome === 'approved' && withhold })
          .then(() => {
            onDone();
            return `${c.act}: ${outcome}.`;
          }),
      QUEUE,
    );
  return (
    <div className={css.column}>
      {c.artifact && (
        <p className={css.meta}>
          Approving authorizes {c.artifact} at its head now{c.action ? `, for ${c.action}` : ''}
          {c.destination ? ` to ${c.destination}` : ''}: this revision, this destination, this action. An edit after you approve opens the review again.
        </p>
      )}
      <TextArea label="Your note (they read it)" value={note} onChange={(e) => setNote(e.target.value)} />
      {c.action && (
        <label className={css.check}>
          <input type="checkbox" checked={withhold} onChange={(e) => setWithhold(e.target.checked)} /> Approve keeping it where it is (skips the {c.action})
        </label>
      )}
      <Select label="If refused, the work goes back to" value={returnTo} onChange={setReturnTo}>
        <option value="">{c.throwback ? `${c.throwback} (the template's default)` : 'Choose an earlier activity'}</option>
        {earlier.map((a: QueueActivity) => (
          <option key={a.act_id} value={a.act_id}>
            {a.act_id} {a.type}
          </option>
        ))}
      </Select>
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={act.busy || !note.trim()} onClick={() => decide('approved')}>
          Approve
        </button>
        <button type="button" className={css.secondary} disabled={act.busy || !note.trim()} onClick={() => decide('changes')}>
          Request changes
        </button>
        <button type="button" className={css.quiet} disabled={act.busy || !note.trim()} onClick={() => decide('declined')}>
          Decline
        </button>
      </div>
      <Said said={act.said} />
    </div>
  );
}

/** A task's page (§2.4): its outcome, layers in order with the open one marked, what waits on it, its history. */
function TaskPanel({ number, names, overview, onClose }: { number: number; names: Names; overview: QueueOverview; onClose: () => void }) {
  const page = useQuery({ queryKey: [...QUEUE, 'task', number], queryFn: () => api.queueTask(number) });
  const act = useAct();
  const [note, setNote] = useState('');
  const [slot, setSlot] = useState('');
  const [artifact, setArtifact] = useState('');
  if (!page.data) return <Card title={`Task #${number}`}>{page.isError ? <p className={css.refused}>Not found.</p> : <p className={css.note}>Reading…</p>}</Card>;
  const { task, layers, waiting, history }: QueueTaskPage = page.data;
  const slots = Array.from(new Set(layers.flat().flatMap((a) => (a.artifact?.startsWith('slot:') ? [a.artifact.slice(5)] : []))));
  return (
    <Card title={`Task #${task.number} · ${task.title}`}>
      <button type="button" className={css.back} onClick={onClose}>
        ‹ Close
      </button>
      <p className={css.text}>Done when: {task.outcome}</p>
      <p className={css.meta}>
        {task.project} · owner {nameOf(names, task.owner)} · {task.status} · index {task.index_doc}
        {task.links.length > 0 ? ` · links ${task.links.join(', ')}` : ''}
      </p>
      <ol className={css.list}>
        {layers.map((layer, i) => (
          <li key={i}>
            <span className={css.subheading}>
              Layer {i + 1}
              {task.open_layer === i ? ' · open' : ''}
            </span>
            <div className={css.chips}>
              {layer.map((a) => (
                <span key={a.act_id} className={css.chip} title={a.note ?? a.reason ?? ''}>
                  {a.act_id} {a.type} · {nameOf(names, a.assignee)} · {a.view}
                  {a.imported ? ' · imported' : ''}
                  {a.artifact ? ` · ${a.artifact}${pin(a.approved_pin ?? a.pin)}` : ''}
                  {a.view === 'blocked' && a.waits_on ? ` · waits on #${a.waits_on}` : ''}
                </span>
              ))}
            </div>
          </li>
        ))}
      </ol>
      {waiting.length > 0 && <p className={css.meta}>Waiting on this task: {waiting.map((w) => `${w.act_id} ${w.type}`).join(', ')}</p>}
      {task.status === 'open' && slots.length > 0 && (
        <div className={css.row}>
          <Select label="Open slot" value={slot} onChange={setSlot}>
            <option value="">Choose</option>
            {slots.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </Select>
          <Field label="Its citation" value={artifact} onChange={(e) => setArtifact(e.target.value)} />
          <button type="button" className={css.secondary} disabled={act.busy || !slot || !artifact.trim()} onClick={() => void act.run(() => api.queueFillSlot(task.number, slot, artifact.trim()).then(() => `slot:${slot} is ${artifact.trim()}.`), QUEUE)}>
            Fill
          </button>
        </div>
      )}
      <details>
        <summary className={css.subheading}>History · {history.length}</summary>
        <ul className={css.list}>
          {history.map((h, i) => (
            <li key={i} className={css.meta}>
              {new Date(h.at).toLocaleString()} · {[h.act_id, h.what, h.outcome].filter(Boolean).join(' ')}
              {h.pin ? ` ${pin(h.pin)}` : ''} · {h.actor_id ? nameOf(names, `${h.actor_kind}:${h.actor_id}`) : h.actor_kind}
              {h.note ? `: ${h.note}` : ''}
            </li>
          ))}
        </ul>
      </details>
      {task.status === 'open' && (task.owner === overview.me || overview.me.startsWith('witness:')) && (
        <LayerEditor task={task} layers={layers} names={names} overview={overview} />
      )}
      {task.status === 'open' && (task.owner === overview.me || overview.me.startsWith('witness:')) && (
        <div className={css.row}>
          <Field label="Why it is dropped" value={note} onChange={(e) => setNote(e.target.value)} />
          <Confirm label="Drop the task" confirm="Drop it? What waits on it is released." disabled={act.busy || !note.trim()} onConfirm={() => void act.run(() => api.queueDrop(task.number, note).then(() => `Task #${task.number} dropped.`), QUEUE)} />
        </div>
      )}
      <Said said={act.said} />
    </Card>
  );
}

type Draft = { id?: string; type: string; assignee: string; locked: boolean };

/**
 * A task's layers edited after it is open (sunna#85): what has started,
 * and every layer before the open one, is shown locked; pending
 * activities move between the open and later layers, or go; new ones and
 * new layers are added from the open layer on. Saved whole, with a note.
 */
function LayerEditor({ task, layers, names, overview }: { task: QueueTaskPage['task']; layers: QueueActivity[][]; names: Names; overview: QueueOverview }) {
  const act = useAct();
  const open = task.open_layer ?? layers.length;
  const initial = (): Draft[][] => layers.map((l, i) => l.map((a) => ({ id: a.act_id, type: a.type, assignee: a.assignee, locked: i < open || a.status !== 'pending' })));
  const [draft, setDraft] = useState<Draft[][] | null>(null);
  const [note, setNote] = useState('');
  const [type, setType] = useState('');
  const [assignee, setAssignee] = useState(overview.me);
  if (!draft)
    return (
      <div>
        <button type="button" className={css.secondary} onClick={() => setDraft(initial())}>
          Edit layers
        </button>
      </div>
    );
  const move = (i: number, j: number, to: number) =>
    setDraft(draft.map((l, k) => (k === i ? l.filter((_, x) => x !== j) : k === to ? [...l, draft[i][j]] : l)).filter((l, k) => l.length > 0 || k >= open));
  const remove = (i: number, j: number) => setDraft(draft.map((l, k) => (k === i ? l.filter((_, x) => x !== j) : l)));
  const add = (i: number) => {
    if (!type.trim()) return;
    const entry: Draft = { type: type.trim(), assignee, locked: false };
    setDraft(i >= draft.length ? [...draft, [entry]] : draft.map((l, k) => (k === i ? [...l, entry] : l)));
    setType('');
  };
  const save = () => {
    const layersOut = draft.filter((l) => l.length > 0).map((l) => l.map((d) => (d.id ? { id: d.id } : { type: d.type, assignee: d.assignee })));
    void act.run(
      () =>
        api.queueEditLayers(task.number, layersOut, note).then(() => {
          setDraft(null);
          setNote('');
          return `Task #${task.number}'s layers saved.`;
        }),
      QUEUE,
    );
  };
  return (
    <div className={css.column}>
      <span className={css.subheading}>Editing layers</span>
      <ol className={css.list}>
        {[...draft, []].map((layer, i) => (
          <li key={i}>
            <span className={css.meta}>{i < draft.length ? `Layer ${i + 1}${i < open ? ' · closed' : i === open ? ' · open' : ''}` : 'A new layer'}</span>
            <div className={css.chips}>
              {layer.map((d, j) => (
                <span key={d.id ?? `new-${i}-${j}`} className={css.chip}>
                  {d.id ?? 'new'} {d.type} · {nameOf(names, d.assignee)}
                  {!d.locked && i > open && (
                    <button type="button" className={css.quiet} aria-label={`Move ${d.type} up a layer`} onClick={() => move(i, j, i - 1)}>
                      ↑
                    </button>
                  )}
                  {!d.locked && (
                    <button type="button" className={css.quiet} aria-label={`Move ${d.type} down a layer`} onClick={() => (i + 1 >= draft.length ? setDraft([...draft.map((l, k) => (k === i ? l.filter((_, x) => x !== j) : l)), [d]]) : move(i, j, i + 1))}>
                      ↓
                    </button>
                  )}
                  {!d.locked && (
                    <button type="button" className={css.quiet} aria-label={`Remove ${d.type}`} onClick={() => remove(i, j)}>
                      ×
                    </button>
                  )}
                </span>
              ))}
              {i >= open && (
                <button type="button" className={css.quiet} disabled={!type.trim()} onClick={() => add(i)}>
                  + here
                </button>
              )}
            </div>
          </li>
        ))}
      </ol>
      <div className={css.row}>
        <Field label="A new activity's verb" value={type} onChange={(e) => setType(e.target.value)} />
        <Select label="For" value={assignee} onChange={setAssignee}>
          {overview.members.map((m) => (
            <option key={m.assignee} value={m.assignee}>
              {m.name}
            </option>
          ))}
          <option value="unknown">Holder not known yet</option>
        </Select>
      </div>
      <Field label="Why (the history keeps it)" value={note} onChange={(e) => setNote(e.target.value)} />
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={act.busy || !note.trim()} onClick={save}>
          Save the layers
        </button>
        <button type="button" className={css.quiet} onClick={() => setDraft(null)}>
          Cancel
        </button>
      </div>
      <Said said={act.said} />
    </div>
  );
}

/**
 * A new task (§2.4, §6.2): from a template, its design slot filled; work
 * already under way starts at the layer it stands at, every earlier one
 * imported done with its links, and carrying no approvals.
 */
function NewTask({ overview }: { overview: QueueOverview }) {
  const act = useAct();
  const [project, setProject] = useState(overview.projects[0]?.slug ?? '');
  const [newProject, setNewProject] = useState('');
  const [template, setTemplate] = useState(overview.templates[0]?.name ?? '');
  const [title, setTitle] = useState('');
  const [slug, setSlug] = useState('');
  const [outcome, setOutcome] = useState('');
  const [design, setDesign] = useState('');
  const [start, setStart] = useState('1');
  const [links, setLinks] = useState('');
  const chosen = overview.templates.find((t) => t.name === template);
  const open = () =>
    void act.run(async () => {
      let p = project;
      if (newProject.trim()) {
        p = slugify(newProject);
        await api.queueOpenProject(p, newProject.trim());
      }
      const { number } = await api.queueOpenTask({
        project: p,
        slug: slug.trim() || slugify(title),
        title: title.trim(),
        outcome: outcome.trim(),
        template,
        slots: design.trim() ? { design: design.trim() } : undefined,
        start_layer: Number(start) > 1 ? Number(start) : undefined,
        links: links.trim() ? links.split(/[\s,]+/).filter(Boolean) : undefined,
      });
      setTitle('');
      setSlug('');
      setOutcome('');
      setDesign('');
      setLinks('');
      return `Opened task #${number}.`;
    }, QUEUE);
  if (overview.templates.length === 0) return null;
  return (
    <Card title="New task">
      <Select label="Project" value={project} onChange={setProject}>
        {overview.projects
          .filter((p) => p.status === 'open')
          .map((p) => (
            <option key={p.slug} value={p.slug}>
              {p.name}
            </option>
          ))}
      </Select>
      <Field label="Or a new project's name" value={newProject} onChange={(e) => setNewProject(e.target.value)} />
      <Select label="Template" value={template} onChange={setTemplate}>
        {overview.templates.map((t) => (
          <option key={t.name} value={t.name}>
            {t.name}: {t.title}
          </option>
        ))}
      </Select>
      <Field label="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
      <Field label="Slug (from the title if left empty)" value={slug} onChange={(e) => setSlug(e.target.value)} />
      <TextArea label="Done when" value={outcome} onChange={(e) => setOutcome(e.target.value)} />
      <Field label="The design's citation (e.g. lily:design/queue-ia)" value={design} onChange={(e) => setDesign(e.target.value)} />
      <Select label="Where the work stands" value={start} onChange={setStart}>
        {(chosen?.layers ?? []).map((layer, i) => (
          <option key={i} value={String(i + 1)}>
            Layer {i + 1}: {layer.map((s) => s.type).join(', ')}
            {i === 0 ? ' (new work)' : ''}
          </option>
        ))}
      </Select>
      {Number(start) > 1 && <Field label="What already exists, by citation (space-separated)" value={links} onChange={(e) => setLinks(e.target.value)} />}
      <div>
        <button type="button" className={css.primary} disabled={act.busy || !title.trim() || !outcome.trim() || (!project && !newProject.trim())} onClick={open}>
          Open the task
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}


/**
 * The witness's setup (§6.2, §7): whose Claude Code is (read, not set), the
 * templates copied from the platform's starters, and the cutover: the
 * old queue committed first, then the house queue turned on naming that
 * commit, and the one-step revert.
 */
function Setup({ overview: q, names }: { overview: QueueOverview; names: Names }) {
  const act = useAct();
  const [commit, setCommit] = useState(q.commit ?? '');
  const [note, setNote] = useState('');
  if (!q.me.startsWith('witness:')) return null;
  const missing = q.starters.filter((s) => !q.templates.some((t) => t.name === s.name));
  return (
    <Card title="Setting up the house queue" witness>
      <p className={css.note}>Claude Code is reached through {q.carrier ? nameOf(names, q.carrier) : 'nobody yet: no resident has a Claude Code conversation'}: a reviewed deliver step in her work, never directly.</p>
      <p className={css.note}>Templates: {q.templates.length ? q.templates.map((t) => t.name).join(', ') : 'none yet'}.</p>
      {missing.map((s) => (
        <button key={s.name} type="button" className={css.secondary} disabled={act.busy} onClick={() => void act.run(() => api.queueDefineTemplate(s.name, s.name).then(() => `${s.name} is in the house.`), QUEUE)}>
          Add {s.name} ({s.title})
        </button>
      ))}
      {q.cut_over ? (
        <>
          <p className={css.note}>
            On since {q.cut_at ? new Date(q.cut_at).toLocaleString() : '—'}; the old queue is committed at {q.commit?.slice(0, 7)} and kept read-only.
          </p>
          <Field label="Why it goes back" value={note} onChange={(e) => setNote(e.target.value)} />
          <Confirm label="Revert to the old queue" confirm="Revert? The old queue's loop and screens come back on." disabled={act.busy || !note.trim()} onConfirm={() => void act.run(() => api.queueCutBack(note).then(() => 'Reverted.'), QUEUE)} />
        </>
      ) : (
        <>
          <div className={css.row}>
            <button type="button" className={css.secondary} disabled={act.busy} onClick={() => void act.run(() => api.queueSnapshot().then((r) => (setCommit(r.commit), `The old queue is committed at ${r.commit.slice(0, 7)}.`)), QUEUE)}>
              Commit the old queue
            </button>
            {commit && <span className={css.mono}>{commit.slice(0, 7)}</span>}
          </div>
          <Field label="Why it goes on now" value={note} onChange={(e) => setNote(e.target.value)} />
          <Confirm label="Turn the house queue on" confirm="Turn it on? The old queues go read-only." disabled={act.busy || !commit || !note.trim() || q.templates.length === 0} onConfirm={() => void act.run(() => api.queueCutOver(commit, note).then(() => 'The house queue is on.'), QUEUE)} />
        </>
      )}
      <Said said={act.said} />
    </Card>
  );
}
