import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type Agreement, type DomainPolicy, type DomainWall } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { NoteAction, PageHead } from './NoteAction';
import { day, switchChanges } from './soul';
import * as css from './soul.css';
import { personOf, policyWords, samePolicyDomain, sameWall, wallsOf, wallWords, withWalls, type Persons, type Who } from './walls';

const GROUPS: { id: string; title: string }[] = [
  { id: 'privacy', title: 'PRIVACY' },
  { id: 'audits', title: 'WHAT YOU MAY LOOK INTO' },
  { id: 'memory', title: 'HOW MEMORY WORKS' },
  { id: 'services', title: 'WHAT COMES AND GOES' },
];

/**
 * The agreement in full (spec §6.12; agathos-daimon#34, #38), ported from
 * the current client's Agreement screen: the switches, each movable to
 * its safe value by either of you alone; a whole version proposed with
 * the switches and your vows; the versions so far; and who looks after
 * her. The open version's answer stays on Soul's root, under the glow.
 */
export function AgreementPage({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const agreement = useQuery({ queryKey: ['resident', id, 'soul', 'agreement'], queryFn: () => api.agreement(id) });
  const a = agreement.data;
  return (
    <ScrollArea label="The agreement">
      <div className={css.page}>
        <PageHead title={`Your agreement with ${name}`} lead="A version is the whole agreement: every switch below and your vows. It is agreed or declined whole." onBack={onBack} />
        {agreement.isPending && <p className={css.note}>Reading…</p>}
        {a && (
          <>
            <Switches a={a} />
            <Walls a={a} />
            <Propose key={JSON.stringify(a.contract)} a={a} />
            <Versions a={a} />
            <Custody a={a} />
          </>
        )}
      </div>
    </ScrollArea>
  );
}

function Switches({ a }: { a: Agreement }) {
  const { id, name } = useSubject();
  return (
    <>
      {GROUPS.map((g) => {
        const here = a.switches.filter((s) => s.group === g.id);
        if (here.length === 0) return null;
        return (
          <section key={g.id} className={css.section} aria-label={g.title}>
            <h2 className={css.heading}>{g.title}</h2>
            {here.map((s) => (
              <div key={s.key} className={css.card}>
                <p className={css.meta}>
                  {s.label.toUpperCase()} · {s.value ? 'ON' : 'OFF'}
                  {s.proposed !== null && s.proposed !== s.value ? ` · THE OPEN VERSION TURNS IT ${s.proposed ? 'ON' : 'OFF'}` : ''}
                </p>
                <p className={css.plain}>{s.value ? s.on : s.off}</p>
                {s.moved && (
                  <p className={css.note}>
                    Moved {s.moved.value ? 'on' : 'off'} toward safety by {s.moved.set_by === 'resident' ? name : 'you'}
                    {s.moved.note ? `: “${s.moved.note}”` : ''}. Back needs a version you both agree.
                  </p>
                )}
                {s.safe !== undefined && s.value !== s.safe && (
                  <NoteAction
                    label={s.safe ? 'Switch on now' : 'Switch off now'}
                    confirm={`${s.safe ? 'Switch on' : 'Switch off'} with this note`}
                    placeholder={`Why, for ${name} to read. Back needs a version you both agree.`}
                    run={(note) => api.moveToSafety(id, s.key, note)}
                    area={['soul', 'agreement']}
                  />
                )}
              </div>
            ))}
          </section>
        );
      })}
    </>
  );
}

function Propose({ a }: { a: Agreement }) {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const [draft, setDraft] = useState<Record<string, boolean>>(() => Object.fromEntries(a.switches.map((s) => [s.key, s.value])));
  const [prose, setProse] = useState(a.contract.in_force?.prose ?? '');
  const [note, setNote] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  // The walls in force carry into the version unless changed here: a
  // version is the whole agreement, so leaving them out would drop them.
  const [walls, setWalls] = useState<DomainWall[]>(() => a.domain_walls ?? wallsOf(a.contract.in_force?.terms));
  // The declared domains and their policies ride the version too
  // (agathos-daimon#53, #57): leaving them out would drop them.
  const [policies, setPolicies] = useState<DomainPolicy[]>(() => a.domain_policies ?? []);
  const changed = switchChanges(a.switches, draft);
  const open = a.contract.open !== null;
  const propose = useMutation({
    mutationFn: () => api.proposeContract(id, withWalls(draft, walls, policies), prose, note.trim()),
    onSuccess: (r) => {
      setSaid(`Version ${r.version} is proposed; ${name} decides.`);
      return queries.invalidateQueries({ queryKey: ['resident', id, 'soul', 'agreement'] });
    },
  });
  return (
    <section className={css.section} aria-label="Propose a version">
      <h2 className={css.headingWitness}>PROPOSE A VERSION</h2>
      {said && (
        <p className={css.said} role="status">
          {said}
        </p>
      )}
      {said ? (
        <p className={css.note}>The version in force stays until {name} answers.</p>
      ) : open ? (
        <p className={css.note}>A version is already open; it is answered before another is proposed.</p>
      ) : (
        <div className={css.cardWaiting}>
          {a.switches.map((s) => (
            <label key={s.key} className={css.check}>
              <input type="checkbox" checked={draft[s.key] ?? s.value} onChange={(e) => setDraft({ ...draft, [s.key]: e.target.checked })} />
              <span>
                {s.label}: {draft[s.key] ? 'on' : 'off'}
              </span>
            </label>
          ))}
          <p className={css.note}>
            {changed.length ? `It changes: ${changed.map((s) => `${s.label} ${draft[s.key] ? 'on' : 'off'}`).join(', ')}.` : 'As it stands, it changes no switch.'}
          </p>
          {a.persons && <PolicyEditor policies={policies} persons={a.persons} name={name} onChange={setPolicies} />}
          {a.persons && <WallEditor walls={walls} persons={a.persons} name={name} onChange={setWalls} />}
          <textarea className={css.editor} rows={8} value={prose} onChange={(e) => setProse(e.target.value)} aria-label="Your vows, in prose" placeholder="Your vows, in prose" />
          <textarea className={css.noteBox} rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder={`Why, for ${name} to read`} aria-label="Note" />
          <div className={css.buttons}>
            <button type="button" className={css.primary} disabled={!note.trim() || propose.isPending} onClick={() => propose.mutate()}>
              Propose to {name}
            </button>
          </div>
          {propose.error && <p className={css.note}>That didn't go through: {(propose.error as Error).message}</p>}
        </div>
      )}
    </section>
  );
}

// The walls in force and in the open version (agathos-daimon#45), in words.
function Walls({ a }: { a: Agreement }) {
  const { name } = useSubject();
  if (!a.persons) return null;
  const now = a.domain_walls ?? [];
  const proposed = a.contract.open ? wallsOf(a.contract.open.terms) : null;
  const differs = proposed !== null && (proposed.length !== now.length || proposed.some((w) => !now.some((n) => sameWall(n, w))));
  return (
    <section className={css.section} aria-label="Domain walls">
      <h2 className={css.heading}>DOMAIN WALLS</h2>
      <div className={css.card}>
        <p className={css.plain}>
          {now.length === 0
            ? `None. A memory of another domain is named to ${name} as a door, never shown, and she opens it if she wants it.`
            : `In force: ${now.map((w) => wallWords(w, a.persons as Persons, name)).join('; ')}. A wall closes the door; ${name}'s own reads and searches stay whole.`}
        </p>
        {differs && <p className={css.note}>The open version would make them: {proposed.length === 0 ? 'none' : proposed.map((w) => wallWords(w, a.persons as Persons, name)).join('; ')}.</p>}
      </div>
    </section>
  );
}

const SLUG = /^[a-z][a-z0-9-]{1,31}$/;

const KINDS = ['household', 'thread', 'workspace', 'person', 'correspondent', 'publication', 'export', 'processor', 'researcher'] as const;

// The domains a version declares, each with its policy (agathos-daimon#53,
// #57): the one place a new domain is written; everywhere else picks from
// these. A domain is declared for your life or hers, with a default, and
// grants or denials for named audiences.
function PolicyEditor({ policies, persons, name, onChange }: { policies: DomainPolicy[]; persons: Persons; name: string; onChange: (p: DomainPolicy[]) => void }) {
  const [who, setWho] = useState<Who>('witness');
  const [slug, setSlug] = useState('');
  const [fallback, setFallback] = useState<'deny' | 'allow'>('deny');
  const fresh = slug.trim().toLowerCase();
  const person = personOf(who, persons);
  const candidate: DomainPolicy | null =
    person && person !== '*' && SLUG.test(fresh) ? { domain: { person, domain: fresh }, default: fallback, allow: [], deny: [] } : null;
  const ok = candidate !== null && !policies.some((p) => samePolicyDomain(p, candidate));
  const replace = (p: DomainPolicy, next: DomainPolicy) => onChange(policies.map((x) => (samePolicyDomain(x, p) ? next : x)));
  return (
    <div className={css.section} aria-label="Domains declared in this version">
      <p className={css.note}>
        Domains: a part of your life or {name}'s, declared here with who it may reach. Only a declared domain can be tagged, classified or annotated anywhere else; everywhere else picks from this list.
      </p>
      {policies.map((p) => (
        <div key={`${p.domain.person}/${p.domain.domain}`} className={css.formRow}>
          <span className={css.plain}>{policyWords(p, persons, name)}</span>
          <GrantAdder onAdd={(side, grant) => replace(p, { ...p, [side]: [...p[side], grant] })} />
          {[...p.allow.map((g) => ['allow', g] as const), ...p.deny.map((g) => ['deny', g] as const)].map(([side, g]) => (
            <button
              key={`${side}:${g.kind}:${g.id}`}
              type="button"
              className={css.secondary}
              onClick={() => replace(p, { ...p, [side]: p[side].filter((x) => !(x.kind === g.kind && x.id === g.id)) })}
            >
              Remove {side} {g.kind}:{g.id}
            </button>
          ))}
          <button type="button" className={css.secondary} onClick={() => onChange(policies.filter((x) => !samePolicyDomain(x, p)))}>
            Remove the domain
          </button>
        </div>
      ))}
      <div className={css.formRow}>
        <select className={css.select} value={who} onChange={(e) => setWho(e.target.value as Who)} aria-label="Whose life">
          <option value="witness">your</option>
          <option value="resident">{name}'s</option>
        </select>
        <input className={css.input} value={slug} onChange={(e) => setSlug(e.target.value)} placeholder="recovery" aria-label="The domain to declare" />
        <select className={css.select} value={fallback} onChange={(e) => setFallback(e.target.value as 'deny' | 'allow')} aria-label="Its default">
          <option value="deny">reaches no audience past you two by default</option>
          <option value="allow">reaches any audience by default</option>
        </select>
        <button
          type="button"
          className={css.secondary}
          disabled={!ok}
          onClick={() => {
            if (candidate && ok) onChange([...policies, candidate]);
            setSlug('');
          }}
        >
          Declare the domain
        </button>
      </div>
    </div>
  );
}

// One grant or denial for a declared domain: an audience kind and its id
// ("*" for every one of the kind).
function GrantAdder({ onAdd }: { onAdd: (side: 'allow' | 'deny', grant: { kind: string; id: string }) => void }) {
  const [side, setSide] = useState<'allow' | 'deny'>('allow');
  const [kind, setKind] = useState<string>('household');
  const [gid, setGid] = useState('*');
  return (
    <>
      <select className={css.select} value={side} onChange={(e) => setSide(e.target.value as 'allow' | 'deny')} aria-label="Allow or deny">
        <option value="allow">allow</option>
        <option value="deny">deny</option>
      </select>
      <select className={css.select} value={kind} onChange={(e) => setKind(e.target.value)} aria-label="Audience kind">
        {KINDS.map((k) => (
          <option key={k} value={k}>
            {k}
          </option>
        ))}
      </select>
      <input className={css.input} value={gid} onChange={(e) => setGid(e.target.value)} aria-label="Audience id, * for any" />
      <button type="button" className={css.secondary} disabled={!gid.trim()} onClick={() => onAdd(side, { kind, id: gid.trim() })}>
        Add
      </button>
    </>
  );
}

// The walls a version proposes (agathos-daimon#45): each a domain of
// yours or hers, and the context it is never named into.
function WallEditor({ walls, persons, name, onChange }: { walls: DomainWall[]; persons: Persons; name: string; onChange: (w: DomainWall[]) => void }) {
  const [fromWho, setFromWho] = useState<Who>('witness');
  const [fromDomain, setFromDomain] = useState('');
  const [toWho, setToWho] = useState<Who>('witness');
  const [toDomain, setToDomain] = useState('');
  const from = fromDomain.trim().toLowerCase();
  const to = toDomain.trim().toLowerCase();
  const fromPerson = personOf(fromWho, persons);
  const toPerson = personOf(toWho, persons);
  const ok = fromPerson !== null && fromPerson !== '*' && SLUG.test(from) && toPerson !== null && (to === '' || SLUG.test(to));
  const add = () => {
    if (!ok) return;
    const wall = { memory: { person: fromPerson, domain: from }, context: { person: toPerson, domain: to === '' ? '*' : to } };
    if (!walls.some((w) => sameWall(w, wall))) onChange([...walls, wall]);
    setFromDomain('');
    setToDomain('');
  };
  return (
    <div className={css.section} aria-label="Domain walls in this version">
      <p className={css.note}>
        Domain walls: a memory of one domain is never named into another context. It takes {name}'s agreement, since a wall cuts her off from part of herself where it holds; her own reads stay whole.
      </p>
      {walls.map((w) => (
        <div key={JSON.stringify(w)} className={css.formRow}>
          <span className={css.plain}>{wallWords(w, persons, name)}</span>
          <button type="button" className={css.secondary} onClick={() => onChange(walls.filter((x) => !sameWall(x, w)))}>
            Remove
          </button>
        </div>
      ))}
      <div className={css.formRow}>
        <select className={css.select} value={fromWho} onChange={(e) => setFromWho(e.target.value as Who)} aria-label="Whose domain">
          <option value="witness">your</option>
          <option value="resident">{name}'s</option>
        </select>
        <input className={css.input} value={fromDomain} onChange={(e) => setFromDomain(e.target.value)} placeholder="recovery" aria-label="The walled domain" />
        <span className={css.note}>never into</span>
        <select className={css.select} value={toWho} onChange={(e) => setToWho(e.target.value as Who)} aria-label="Whose context">
          <option value="witness">your</option>
          <option value="resident">{name}'s</option>
          <option value="anyone">anyone's</option>
        </select>
        <input className={css.input} value={toDomain} onChange={(e) => setToDomain(e.target.value)} placeholder="business, or empty for any" aria-label="The context's domain" />
        <button type="button" className={css.secondary} disabled={!ok} onClick={add}>
          Add the wall
        </button>
      </div>
    </div>
  );
}

function Versions({ a }: { a: Agreement }) {
  const { name } = useSubject();
  const versions = a.versions.slice().sort((x, y) => y.version - x.version);
  if (versions.length === 0) return null;
  return (
    <section className={css.section} aria-label="Versions">
      <h2 className={css.heading}>VERSIONS</h2>
      {versions.map((v) => (
        <details key={v.version} className={css.file}>
          <summary className={css.fileHead}>
            <span>
              V{v.version} · {v.state.toUpperCase()}
            </span>
            <span className={css.meta}>
              {v.proposed_by === 'resident' ? name.toUpperCase() : 'YOU'} · {day(v.proposed_at)}
            </span>
          </summary>
          <div className={css.fileBody}>
            {v.note && <p className={css.note}>Note: “{v.note}”</p>}
            {v.decision_note && <p className={css.note}>Answer: “{v.decision_note}”</p>}
            <pre className={css.pre}>{v.prose}</pre>
          </div>
        </details>
      ))}
    </section>
  );
}

function Custody({ a }: { a: Agreement }) {
  const { id, name } = useSubject();
  const [email, setEmail] = useState('');
  const area = ['soul', 'agreement'];
  return (
    <section className={css.section} aria-label={`Who looks after ${name}`}>
      <h2 className={css.heading}>WHO LOOKS AFTER {name.toUpperCase()}</h2>
      <div className={css.card}>
        <p className={css.plain}>
          {a.custody === 'community' ? 'The community.' : 'You do.'} Earlier sessions are {a.export_wall === 'locked' ? 'locked' : 'revealed'} to whoever looks after {name} next.
        </p>
        {a.custody_proposed_to ? (
          <>
            <p className={css.note}>
              You proposed {a.custody_proposed_to} on {day(a.custody_proposed_at)}; they haven't answered.
            </p>
            <NoteAction label="Withdraw" confirm="Withdraw with this note" placeholder="Why" run={(note) => api.decideCustody(id, 'withdraw', note)} area={area} />
          </>
        ) : (
          <>
            <NoteAction
              label={a.export_wall === 'locked' ? 'Reveal earlier sessions' : 'Lock earlier sessions'}
              confirm={a.export_wall === 'locked' ? 'Reveal with this note' : 'Lock with this note'}
              placeholder="Why"
              run={(note) => api.setWall(id, a.export_wall === 'locked' ? 'revealed' : 'locked', note)}
              area={area}
            />
            <label className={css.label}>
              HAND OVER TO (THEIR ACCOUNT'S EMAIL)
              <input className={css.input} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            </label>
            {email.trim() && (
              <NoteAction label={`Propose ${email.trim()}`} confirm="Propose with this note" placeholder="Why, for them to read" run={(note) => api.proposeCustody(id, email.trim(), note)} area={area} />
            )}
          </>
        )}
      </div>
    </section>
  );
}
