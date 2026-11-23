import { useState } from 'react';
import { create } from 'zustand';
import { api } from '../../api/client';
import type { QueueOverview, QueueSpec } from '../../api/types';
import { Field, Said, Select } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { HOUSE } from './keys';
import { GATED, glyph, LETS, position, ROLE_WORDS, ROLES, slugify, templateProblems, TYPES, type DrawnLayer, type TemplateSpec } from './queueText';
import { LayersDrawn } from './TaskPage';
import * as w from './work.css';
import { useWorkNav, workPath } from './workRoutes';

const QUEUE = [...HOUSE, 'queue'];

// In the editor an activity is named by a key that travels with it, so
// moving or removing one never points a throwback at another; positions
// ("2.1") are what is shown, checked and saved.
type TemplateDraft = TemplateSpec & { key: string };
let keys = 0;
const fresh = () => `k${(keys += 1)}`;

const draftsOf = (layers: QueueSpec[][]): TemplateDraft[][] => {
  const keyed = layers.map((l) => l.map(() => fresh()));
  const at = (pos: string | null | undefined) => {
    const [l, j] = (pos ?? '').split('.').map(Number);
    return keyed[l - 1]?.[j - 1] ?? null;
  };
  return layers.map((l, i) =>
    l.map((s, j) => ({
      key: keyed[i][j],
      name: s.name ?? '',
      type: s.type ?? '',
      role: s.role ?? 'unknown',
      artifact: s.artifact ?? null,
      destination: s.destination ?? null,
      action: s.action ?? null,
      optional: s.optional === true,
      throwback: at(s.throwback),
    })),
  );
};

/** The drafts as positions: what the shape check reads and the server takes. */
const positioned = (layers: TemplateDraft[][]): TemplateSpec[][] => {
  const where = new Map<string, string>();
  layers.forEach((l, i) => l.forEach((d, j) => where.set(d.key, position(i, j))));
  return layers.map((l) =>
    l.map(({ key: _key, ...s }) => ({
      ...s,
      name: s.name.trim(),
      artifact: s.artifact || null,
      destination: s.destination || null,
      action: s.action || null,
      throwback: (s.throwback && where.get(s.throwback)) || null,
    })),
  );
};

interface Draft {
  name: string;
  title: string;
  layers: TemplateDraft[][];
  /** Slots named before any activity works on them. */
  slots: string[];
}

/** The template being written, kept while its activities' pages open and close; dropped when saved or discarded. */
const useDrafts = create<{ drafts: Record<string, Draft>; put: (key: string, d: Draft) => void; drop: (key: string) => void }>((set) => ({
  drafts: {},
  put: (key, d) => set((s) => ({ drafts: { ...s.drafts, [key]: d } })),
  drop: (key) =>
    set((s) => {
      const { [key]: _gone, ...rest } = s.drafts;
      return { drafts: rest };
    }),
}));

/** A template's draft: kept, else from the house's template of that name, else from the platform's starter, else blank. */
function useDraft(name: string, q: QueueOverview): [Draft, (d: Draft) => void, () => void] {
  const kept = useDrafts((s) => s.drafts[name]);
  const put = useDrafts((s) => s.put);
  const drop = useDrafts((s) => s.drop);
  const from = q.templates.find((t) => t.name === name) ?? q.starters.find((s) => s.name === name);
  const [initial] = useState<Draft>(() => (from ? { name: from.name, title: from.title, layers: draftsOf(from.layers), slots: [] } : { name: '', title: '', layers: [], slots: [] }));
  return [kept ?? initial, (d) => put(name, d), () => drop(name)];
}

const slotsOf = (d: Draft) => [...new Set([...d.layers.flat().flatMap((s) => (s.artifact ? [s.artifact] : [])), ...d.slots])];

/** The template's layers as the task page draws them: slots in place of documents, roles in place of people. */
function drawn(d: Draft): DrawnLayer[] {
  const where = new Map<string, string>();
  d.layers.forEach((l, i) => l.forEach((s, j) => where.set(s.key, position(i, j))));
  return d.layers.map((l, i) => ({
    n: i + 1,
    state: 'later',
    label: l.length === 1 ? '1 activity' : `${l.length} activities`,
    acts: l.map((s, j) => ({ id: position(i, j), name: s.name || '(no name yet)', type: s.type || 'a type', glyph: glyph(s.type), assignee: s.role, view: '', gated: GATED.includes(s.type), slot: s.artifact ?? null })),
  }));
}

function holdLine(s: TemplateDraft, where: Map<string, string>): string {
  const bits = [ROLE_WORDS[s.role] ?? s.role];
  if (s.action) bits.push(`lets ${LETS[s.action] ?? s.action}`);
  if (s.throwback && where.get(s.throwback)) bits.push(`back to ${where.get(s.throwback)?.split('.')[0]}`);
  if (s.optional) bits.push('optional');
  return bits.join(' · ');
}

/**
 * A template, edited like a task (the queue mocks' Template): its name
 * and title, the document slots it works on, its layers drawn with each
 * activity's name and role, and New activity. What the shape rule would
 * refuse is said before saving (sunna#88); tasks already open keep the
 * layers they started with.
 */
export function TemplateEditor({ name, overview: q }: { name: string; overview: QueueOverview }) {
  const nav = useWorkNav();
  const act = useAct();
  const [d, put, drop] = useDraft(name, q);
  const [slot, setSlot] = useState('');
  const [addingSlot, setAddingSlot] = useState(false);
  const inHouse = q.templates.some((t) => t.name === name);
  const users = q.tasks.filter((t) => t.status === 'open' && t.template === name).length;
  const slug = slugify(d.name);
  const problems = templateProblems(positioned(d.layers));
  const where = new Map<string, string>();
  d.layers.forEach((l, i) => l.forEach((s, j) => where.set(s.key, position(i, j))));
  const byPos = new Map(d.layers.flatMap((l, i) => l.map((s, j) => [position(i, j), s] as const)));
  const save = () =>
    void act.run(
      () =>
        api.queueSaveTemplate(slug, d.title.trim(), positioned(d.layers)).then(() => {
          drop();
          if (slug !== name) nav(workPath.template(slug));
          return `${slug} is saved in the house.`;
        }),
      QUEUE,
    );
  return (
    <>
      <button type="button" className={css.back} onClick={() => nav('')}>
        ‹ Templates
      </button>
      <span className={w.meta}>{inHouse ? `in the house · used by ${users} open ${users === 1 ? 'task' : 'tasks'}` : q.starters.some((s) => s.name === name) ? "the platform's starter: saving puts it in the house" : 'a new template'}</span>
      <h1 className={w.pageTitle}>{d.title || d.name || 'A new template'}</h1>
      <section className={css.card} aria-label="Its name">
        <Field label="Name (lowercase, hyphens; the same name replaces it)" value={d.name} onChange={(e) => put({ ...d, name: e.target.value })} />
        <Field label="Title" value={d.title} onChange={(e) => put({ ...d, title: e.target.value })} />
      </section>
      <section className={css.card} aria-label="Documents it works on">
        <h2 className={css.heading}>Documents it works on</h2>
        {slotsOf(d).length === 0 && <p className={css.note}>No slots yet: an activity's Works on names one.</p>}
        <ul className={w.docs}>
          {slotsOf(d).map((s) => {
            const n = d.layers.flat().filter((x) => x.artifact === s).length;
            return (
              <li key={s} className={w.docRow}>
                <div className={w.docMain}>
                  <span>{s}</span>
                  <span className={w.docPath}>{s === 'design' ? 'named when a task opens' : 'filled when a task gives it one'}</span>
                </div>
                <span className={w.role}>{n === 1 ? '1 activity' : `${n} activities`}</span>
              </li>
            );
          })}
        </ul>
        {addingSlot ? (
          <div className={css.row}>
            <Field label="The slot's name (pr, brief…)" value={slot} onChange={(e) => setSlot(e.target.value)} />
            <button
              type="button"
              className={css.secondary}
              disabled={!slugify(slot)}
              onClick={() => {
                put({ ...d, slots: [...new Set([...d.slots, slugify(slot)])] });
                setSlot('');
                setAddingSlot(false);
              }}
            >
              Add the slot
            </button>
          </div>
        ) : (
          <div>
            <button type="button" className={css.quiet} onClick={() => setAddingSlot(true)}>
              + a document slot
            </button>
          </div>
        )}
      </section>
      <section className={css.card} aria-label="Layers">
        <div className={w.top}>
          <h2 className={css.heading}>Layers</h2>
          <button type="button" className={css.secondary} onClick={() => nav(workPath.templateActivity(name, 'new'))}>
            New activity
          </button>
        </div>
        {d.layers.length === 0 && <p className={css.note}>No activities yet.</p>}
        <LayersDrawn layers={drawn(d)} names={{}} me="" onOpen={(at) => nav(workPath.templateActivity(name, at))} hold={(a) => holdLine(byPos.get(a.id) as TemplateDraft, where)} />
      </section>
      {problems.length > 0 && (
        <ul className={css.list} aria-label="Before it can be saved">
          {problems.map((p) => (
            <li key={p} className={css.warn} style={{ fontSize: 13 }}>
              {p}
            </li>
          ))}
        </ul>
      )}
      {problems.length === 0 && d.layers.some((l) => l.some((s) => GATED.includes(s.type))) && <p className={css.note}>Every gated step has its review right before it.</p>}
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={act.busy || !slug || !d.title.trim() || problems.length > 0} onClick={save}>
          Save the template
        </button>
        <button type="button" className={css.quiet} onClick={() => (drop(), nav(''))}>
          Discard changes
        </button>
      </div>
      <span className={css.meta}>Tasks already open keep the layers they started with.</span>
      <Said said={act.said} />
    </>
  );
}

type Fields = Omit<TemplateDraft, 'key'> & { layer: number };

/**
 * One activity of a template (the queue mocks' Template · one activity):
 * its name (every task made from the template shows it), type, the role
 * holding it, its layer, the slot it works on, what approving lets
 * happen and where a refusal goes, and whether it is optional. Saved into
 * the template's draft; the template is saved whole from its page.
 */
export function TemplateActivity({ name, at, overview: q }: { name: string; at: string; overview: QueueOverview }) {
  const nav = useWorkNav();
  const [d, put] = useDraft(name, q);
  const [i, j] = at.split('.').map((x) => Number(x) - 1);
  const s = at === 'new' ? null : (d.layers[i]?.[j] ?? null);
  const [f, setF] = useState<Fields>(() =>
    s ? { ...s, layer: i } : { name: '', type: '', role: 'author', artifact: null, destination: null, action: null, optional: false, throwback: null, layer: Math.max(d.layers.length - 1, 0) },
  );
  if (at !== 'new' && !s) return <p className={css.refused}>{name} has no activity {at}.</p>;
  const set = (patch: Partial<Fields>) => setF({ ...f, ...patch });
  const slots = slotsOf(d);
  const earlier = d.layers.slice(0, f.layer).flatMap((l, a) => l.map((x, b) => ({ key: x.key, at: position(a, b), name: x.name || x.type })));
  const review = f.type === 'review';
  const gated = GATED.includes(f.type);
  const back = () => nav(workPath.template(name));
  const write = (remove: boolean) => {
    const { layer, ...spec } = f;
    const key = s?.key ?? fresh();
    const entry: TemplateDraft = { ...spec, key, destination: review || gated ? spec.destination : null, action: review ? spec.action : null, throwback: review ? spec.throwback : null };
    let layers = d.layers.map((l, a) => (a === i && !remove && layer === i ? l.map((x) => (x.key === key ? entry : x)) : l.filter((x) => x.key !== key)));
    if (!remove && (s === null || layer !== i)) layers = layer >= layers.length ? [...layers, [entry]] : layers.map((l, a) => (a === layer ? [...l, entry] : l));
    // A removed activity takes the throwbacks naming it with it.
    layers = layers.filter((l) => l.length > 0).map((l) => l.map((x) => (remove && x.throwback === key ? { ...x, throwback: null } : x)));
    put({ ...d, layers });
    back();
  };
  return (
    <>
      <button type="button" className={css.back} onClick={back}>
        ‹ {d.name || name}
      </button>
      <span className={w.meta}>{s ? `layer ${i + 1} · ${at}` : 'a new activity'}</span>
      <span className={w.typeWord}>
        {glyph(f.type)} {f.type || 'no type yet'} · in the template
      </span>
      <h1 className={w.pageTitle}>{f.name || 'New activity'}</h1>
      <section className={css.card} aria-label="The activity">
        <Field label="Name" value={f.name} maxLength={80} onChange={(e) => set({ name: e.target.value })} />
        <span className={css.meta}>Every task made from {d.name || 'this template'} shows this name.</span>
        <Select label="Type" value={f.type} onChange={(v) => set({ type: v })}>
          {!f.type && <option value="">Choose…</option>}
          {[...new Set([...TYPES, ...(f.type ? [f.type] : [])])].map((t) => (
            <option key={t} value={t}>
              {glyph(t)} {t}
            </option>
          ))}
        </Select>
        <Select label="Held by" value={f.role} onChange={(v) => set({ role: v })}>
          {ROLES.map((r) => (
            <option key={r} value={r}>
              {ROLE_WORDS[r]}
            </option>
          ))}
        </Select>
        <Select label="Layer" value={String(f.layer)} onChange={(v) => set({ layer: Number(v) })}>
          {Array.from({ length: d.layers.length + 1 }, (_, k) => (
            <option key={k} value={String(k)}>
              {k < d.layers.length ? String(k + 1) : '+ a new layer'}
            </option>
          ))}
        </Select>
        <Select label="Works on" value={f.artifact ?? ''} onChange={(v) => set({ artifact: v || null })}>
          {slots.map((x) => (
            <option key={x} value={x}>
              {x}
            </option>
          ))}
          <option value="">no document</option>
        </Select>
        {review && (
          <Select label="Approving lets" value={f.action ?? ''} onChange={(v) => set({ action: v || null })}>
            <option value="">nothing gated</option>
            {GATED.map((g) => (
              <option key={g} value={g}>
                {LETS[g] ?? g}
              </option>
            ))}
          </Select>
        )}
        {(review || gated) && <Field label="Destination (house, main, email…)" value={f.destination ?? ''} onChange={(e) => set({ destination: e.target.value || null })} />}
        {review && (
          <Select label="If refused, back to" value={f.throwback ?? ''} onChange={(v) => set({ throwback: v || null })}>
            <option value="">the reviewer picks</option>
            {earlier.map((x) => (
              <option key={x.key} value={x.key}>
                {x.at.split('.')[0]} · {x.name}
              </option>
            ))}
          </Select>
        )}
        <label className={css.check}>
          <input type="checkbox" checked={f.optional === true} onChange={(e) => set({ optional: e.target.checked })} /> Optional: whoever holds it may skip it
        </label>
        <div className={css.row}>
          <button type="button" className={css.primary} disabled={!f.name.trim() || !f.type} onClick={() => write(false)}>
            Save
          </button>
          <button type="button" className={css.quiet} onClick={back}>
            Cancel
          </button>
          {s && (
            <button type="button" className={css.quiet} onClick={() => write(true)}>
              Remove
            </button>
          )}
        </div>
        <span className={css.meta}>Saved into the template here; the template itself is saved from its page.</span>
      </section>
    </>
  );
}
