import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { QueueCard, QueueOverview } from '../../api/types';
import { Card, Confirm, Field, Said, Select, TextArea } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { useShell } from '../state/store';
import { DocumentScreen } from './DocumentScreen';
import { HOUSE } from './keys';
import { actName, blockedLine, holdersOf, nameOf, since, slugify, stepStatus, taskSummaries, unpinned, type Names, type TaskSummary } from './queueText';
import { ActivityPage, NewActivityPage, TaskPage, Who } from './TaskPage';
import { TemplateActivity, TemplateEditor } from './TemplateEditor';
import * as w from './work.css';
import { parseWorkPath, useHouseLive, useWorkNav, workPath } from './workRoutes';

/** The house queue's query keys: under the house's root, so a house write reads them again too. */
const QUEUE = [...HOUSE, 'queue'];

/**
 * Work (screen:next-house, sunna#80, #90, #91; the queue mocks of
 * 2026-11-23): the house queue as its tasks, each page a path under
 * `#/settings/queue/` the browser's back steps through: the task list,
 * a task, an activity, a new activity, a new task, a template and its
 * activities, and the one document screen. Live on the household's
 * channel, never a timer (sunna#87).
 */
export function HouseWork() {
  const overview = useQuery({ queryKey: QUEUE, queryFn: api.queue });
  useHouseLive(overview.data?.household_id);
  const path = useShell((s) => s.pagePath);
  const nav = useWorkNav();

  if (overview.isPending) return <p className={css.note}>Reading…</p>;
  if (!overview.data) return <p className={css.refused}>The house queue could not be read.</p>;
  const q = overview.data;
  // The viewer's own are "you": the house's name for a witness is long.
  const names: Names = { ...Object.fromEntries(q.members.map((m) => [m.assignee, m.name])), [q.me]: 'you' };
  const route = parseWorkPath(path);
  switch (route.page) {
    case 'task':
      return <TaskPage number={route.number} names={names} overview={q} />;
    case 'activity':
      return <ActivityPage number={route.number} actId={route.act} names={names} overview={q} />;
    case 'new-activity':
      return <NewActivityPage number={route.number} names={names} overview={q} />;
    case 'new-task':
      return <NewTask overview={q} citation={route.citation} onBack={() => (route.citation ? window.history.back() : nav(''))} />;
    case 'template':
      return <TemplateEditor key={route.name} name={route.name} overview={q} />;
    case 'template-activity':
      return <TemplateActivity key={`${route.name}/${route.at}`} name={route.name} at={route.at} overview={q} />;
    case 'doc':
      return <DocumentScreen citation={route.citation} onBack={() => window.history.back()} />;
    default:
      return <TaskList overview={q} names={names} />;
  }
}

/**
 * The task list (the queue mocks' Work): task cards only, activities
 * live on their task's page. Waiting on me shows Your move (a ready or
 * active activity of the open layer is yours); All open adds Under way
 * elsewhere; Project narrows both.
 */
function TaskList({ overview: q, names }: { overview: QueueOverview; names: Names }) {
  const nav = useWorkNav();
  const cards = useQuery({ queryKey: [...QUEUE, 'activities', 'anyone'], queryFn: () => api.queueActivities({ who: 'anyone' }) });
  // Whose queue (the witness, 2026-11-23): yours, any member's, or everyone's.
  const [whose, setWhose] = useState<string>(q.me);
  const [project, setProject] = useState('');
  const tasks = q.tasks.filter((t) => !project || t.project === project);
  const all = whose === 'all';
  const { mine, others, later } = taskSummaries(tasks, cards.data ?? [], all ? q.me : holdersOf(whose));
  const you = whose === q.me || all;
  const who = you ? 'Your' : `${nameOf(names, whose)}'s`;
  const members = q.members.filter((m) => m.assignee !== q.me);
  return (
    <>
      {!q.cut_over && (
        <p className={css.note}>
          The house queue is not on yet: the old work queues still run. Build the templates and move the work in progress, then turn it on below.
        </p>
      )}
      <div className={w.top}>
        <h1 className={w.pageTitle}>Work</h1>
        {q.templates.length > 0 && (
          <button type="button" className={css.primary} onClick={() => nav(workPath.newTask())}>
            New task
          </button>
        )}
      </div>
      <div className={w.segmented} role="group" aria-label="Whose queue">
        <button type="button" className={w.segment} aria-pressed={whose === q.me} onClick={() => setWhose(q.me)}>
          Mine
        </button>
        {members.map((m) => (
          <button key={m.assignee} type="button" className={w.segment} aria-pressed={whose === m.assignee} onClick={() => setWhose(m.assignee)}>
            {m.name}
          </button>
        ))}
        <button type="button" className={w.segment} aria-pressed={all} onClick={() => setWhose('all')}>
          Everyone
        </button>
      </div>
      <div className={w.segmented} role="group" aria-label="Filters">
        <select className={w.select} aria-label="Project" value={project} onChange={(e) => setProject(e.target.value)}>
          <option value="">Project: all</option>
          {q.projects.map((p) => (
            <option key={p.slug} value={p.slug}>
              {p.name}
            </option>
          ))}
        </select>
      </div>
      {q.cut_over && <QueueSwitch overview={q} />}
      {q.cut_over && whose.startsWith('resident:') && <LineStatus residentId={whose.slice('resident:'.length)} name={nameOf(names, whose)} />}
      {cards.isPending && <p className={css.note}>Reading…</p>}
      {cards.data && (
        <>
          <h2 className={w.section}>{who} move · {mine.length}</h2>
          {mine.length === 0 && <p className={css.note}>{you ? 'Nothing waits on you.' : `Nothing waits on ${nameOf(names, whose)}.`}</p>}
          {mine.map((s) => (
            <TaskCard key={s.task.number} s={s} names={names} me={q.me} mine />
          ))}
          {!all && later.length > 0 && (
            <>
              <h2 className={w.section}>{you ? 'Yours' : `${nameOf(names, whose)}'s`} later · {later.length}</h2>
              {later.map((s) => (
                <TaskCard key={s.task.number} s={s} names={names} me={q.me} />
              ))}
            </>
          )}
          {all && (
            <>
              <h2 className={w.section}>Under way elsewhere · {others.length}</h2>
              {others.length === 0 && <p className={css.note}>Nothing else is open.</p>}
              {others.map((s) => (
                <TaskCard key={s.task.number} s={s} names={names} me={q.me} />
              ))}
            </>
          )}
        </>
      )}
      <Templates overview={q} />
      <Setup overview={q} />
    </>
  );
}

/**
 * The house queue's one switch (sunna#94; the witness, 2026-11-23: "the
 * queue is either running or it's not"): it runs unless paused, for every
 * resident at once; a witness pauses or resumes it, with a note.
 */
function QueueSwitch({ overview: q }: { overview: QueueOverview }) {
  const queries = useQueryClient();
  const [note, setNote] = useState('');
  const flip = useMutation({
    mutationFn: () => (q.paused ? api.queueResume(note || 'running again') : api.queuePause(note || 'paused')),
    onSettled: () => {
      setNote('');
      void queries.invalidateQueries({ queryKey: QUEUE });
    },
  });
  const witness = q.me.startsWith('witness:');
  return (
    <div className={w.segmented} role="group" aria-label="The house queue">
      <span className={css.note}>{q.paused ? `The queue is paused${q.paused_at ? ` since ${since(q.paused_at)} ago` : ''}: nothing starts on anyone's line.` : 'The queue is running: each resident takes her next ready step.'}</span>
      {witness && (
        <>
          <input className={w.select} aria-label="Why (a note)" placeholder="Why (optional)" value={note} onChange={(e) => setNote(e.target.value)} />
          <button type="button" className={q.paused ? css.primary : css.secondary} disabled={flip.isPending} onClick={() => flip.mutate()}>
            {q.paused ? 'Resume' : 'Pause'}
          </button>
        </>
      )}
    </div>
  );
}

/**
 * Where a resident's line stands (the witness, 2026-11-23: steps that
 * looked stalled were waiting on her free time): what it runs, or why it
 * rests. Read only: the queue's one switch is above.
 */
function LineStatus({ residentId, name }: { residentId: string; name: string }) {
  const line = useQuery({ queryKey: ['resident', residentId, 'settings', 'work'], queryFn: () => api.work(residentId), refetchOnWindowFocus: true });
  if (!line.data) return null;
  const q = line.data;
  const now = q.running_act ? `running ${q.running_act}${q.running_task ? ` of task #${q.running_task}` : ''}` : (q.rested ?? 'idle');
  return <p className={css.note}>{name}'s line: {now}</p>;
}

/**
 * A task's card: title and number, project and the layer it is at, its
 * documents as chips (each opens the document screen), what is in
 * progress now with whose it is, and a blocked task's blocker and that
 * task's next action.
 */
function TaskCard({ s, names, me, mine = false }: { s: TaskSummary; names: Names; me: string; mine?: boolean }) {
  const nav = useWorkNav();
  const docs = (s.task.documents ?? []).filter((d) => d.citation);
  const open = () => nav(workPath.task(s.task.number));
  return (
    <div
      role="link"
      tabIndex={0}
      className={mine ? w.cardMine : w.card}
      aria-label={`Task #${s.task.number}: ${s.task.title}`}
      onClick={open}
      onKeyDown={(e) => {
        if (e.key === 'Enter') open();
      }}
    >
      <div className={w.cardHead}>
        <span className={w.cardTitle}>{s.task.title}</span>
        <span className={w.number}>#{s.task.number}</span>
      </div>
      <span className={w.meta}>
        {s.task.project} · layer {s.at} of {s.of}
      </span>
      {docs.length > 0 && (
        <div className={w.chips}>
          {docs.map((d) => (
            <button
              key={d.key}
              type="button"
              className={w.docChip}
              title={`${d.role}: ${d.citation}`}
              onClick={(e) => {
                e.stopPropagation();
                nav(workPath.doc(d.citation as string));
              }}
            >
              {unpinned(d.citation as string)}
            </button>
          ))}
        </div>
      )}
      {s.now.map((c: QueueCard) => (
        <div key={c.act} className={w.nowRow}>
          <span className={`${w.dot} ${w.viewColor[c.view]}`} aria-hidden />
          <span>{actName(c)}</span>
          {c.name && <span className={w.typeWord}>{c.type}</span>}
          <Who assignee={c.assignee} names={names} me={me} />
          <span className={w.stepStatus}>{stepStatus(c)}</span>
        </div>
      ))}
      {s.blocked && <span className={w.blocked}>{blockedLine(s.blocked, names)}</span>}
    </div>
  );
}

/** The house's templates: each opens in the template editor; a starter not in the house yet opens to be saved there; or a blank one. */
function Templates({ overview: q }: { overview: QueueOverview }) {
  const nav = useWorkNav();
  const starters = q.starters.filter((s) => !q.templates.some((t) => t.name === s.name));
  return (
    <Card title={`Templates · ${q.templates.length}`}>
      {q.templates.length === 0 && <p className={css.note}>None in the house yet.</p>}
      <div className={css.column}>
        {q.templates.map((t) => (
          <button key={t.name} type="button" className={css.linkButton} onClick={() => nav(workPath.template(t.name))}>
            {t.name}: {t.title} ›
          </button>
        ))}
        {starters.map((t) => (
          <button key={t.name} type="button" className={css.linkButton} onClick={() => nav(workPath.template(t.name))}>
            {t.name}: {t.title} (the platform's starter) ›
          </button>
        ))}
      </div>
      <div>
        <button type="button" className={css.secondary} onClick={() => nav(workPath.template('new'))}>
          A new template
        </button>
      </div>
    </Card>
  );
}

/**
 * A new task (§2.4, §6.2): from a template, its design slot filled; work
 * already under way starts at the layer it stands at, every earlier one
 * imported done with its links, and carrying no approvals.
 */
function NewTask({ overview, citation, onBack }: { overview: QueueOverview; citation: string | null; onBack: () => void }) {
  const nav = useWorkNav();
  const act = useAct();
  const [project, setProject] = useState(overview.projects[0]?.slug ?? '');
  const [newProject, setNewProject] = useState('');
  const [template, setTemplate] = useState(overview.templates[0]?.name ?? '');
  const [title, setTitle] = useState('');
  const [slug, setSlug] = useState('');
  const [outcome, setOutcome] = useState('');
  const [design, setDesign] = useState(citation ?? '');
  const [as, setAs] = useState<'design' | 'source'>('design');
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
        slots: design.trim() && as === 'design' ? { design: design.trim() } : undefined,
        start_layer: Number(start) > 1 ? Number(start) : undefined,
        links: [...(links.trim() ? links.split(/[\s,]+/).filter(Boolean) : []), ...(design.trim() && as === 'source' ? [design.trim()] : [])],
      });
      setTitle('');
      setSlug('');
      setOutcome('');
      setDesign('');
      setLinks('');
      nav(workPath.task(number));
      return `Opened task #${number}.`;
    }, QUEUE);
  if (overview.templates.length === 0) return <p className={css.note}>The house has no template yet: a task opens from one.</p>;
  return (
    <>
    <button type="button" className={css.back} onClick={onBack}>
      ‹ Back
    </button>
    <h1 className={w.pageTitle}>New task</h1>
    <Card title="The task">
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
      <Field label="A document's citation (e.g. lily:design/queue-ia)" value={design} onChange={(e) => setDesign(e.target.value)} />
      {design.trim() && (
        <Select label="As" value={as} onChange={(v) => setAs(v as 'design' | 'source')}>
          <option value="design">its design (the design slot: the template's activities work on it)</option>
          <option value="source">a source</option>
        </Select>
      )}
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
    </>
  );
}


/**
 * The witness's setup (§6.2, §7): the
 * templates copied from the platform's starters, and the cutover: the
 * old queue committed first, then the house queue turned on naming that
 * commit, and the one-step revert.
 */
function Setup({ overview: q }: { overview: QueueOverview }) {
  const act = useAct();
  const [commit, setCommit] = useState(q.commit ?? '');
  const [note, setNote] = useState('');
  if (!q.me.startsWith('witness:')) return null;
  const missing = q.starters.filter((s) => !q.templates.some((t) => t.name === s.name));
  return (
    <Card title="Setting up the house queue" witness>
      <p className={css.note}>A resident&apos;s Claude Code runs on her memories: work for it goes through her own reviewed deliver step, never directly.</p>
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
