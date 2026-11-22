import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type Agreement, type DomainPolicy } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { NoteAction, PageHead } from './NoteAction';
import { day, switchChanges } from './soul';
import * as css from './soul.css';
import { personOf, policyWords, samePolicyDomain, withPolicies, type Persons, type Who } from './terms';

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
  // The declared domains and their policies ride the version too
  // (agathos-daimon#53, #57): leaving them out would drop them.
  const [policies, setPolicies] = useState<DomainPolicy[]>(() => a.domain_policies ?? []);
  const changed = switchChanges(a.switches, draft);
  const open = a.contract.open !== null;
  const propose = useMutation({
    mutationFn: () => api.proposeContract(id, withPolicies(draft, policies), prose, note.trim()),
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
          {a.persons && <PolicyEditor policies={policies} persons={a.persons} name={name} households={a.households ?? []} onChange={setPolicies} />}
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

const SLUG = /^[a-z][a-z0-9-]{1,31}$/;

const KINDS = ['household', 'workspace', 'person', 'correspondent', 'publication', 'processor', 'researcher'] as const;

// The domains a version declares, each with its policy (agathos-daimon#53,
// #57): the one place a new domain is written; everywhere else picks from
// these. A domain is declared for your life or hers, with a default, and
// grants or denials for named audiences.
const COMMON_ROOM = { person: '*', domain: 'common-room' };
const isCommonRoom = (p: DomainPolicy) => p.domain.person === '*' && p.domain.domain === 'common-room';
const COMMON_ROOM_DEFAULT =
  'The common room (what no domain names): no policy written, so it reaches every audience but the public ones (publication, processor).';

function PolicyEditor({ policies, persons, name, households, onChange }: { policies: DomainPolicy[]; persons: Persons; name: string; households: Household[]; onChange: (p: DomainPolicy[]) => void }) {
  const [who, setWho] = useState<Who>('witness');
  const [slug, setSlug] = useState('');
  const [fallback, setFallback] = useState<'deny' | 'allow'>('deny');
  const fresh = slug.trim().toLowerCase();
  const person = personOf(who, persons);
  const candidate: DomainPolicy | null =
    person && person !== '*' && SLUG.test(fresh) ? { domain: { person, domain: fresh }, default: fallback, allow: [], deny: [] } : null;
  const ok = candidate !== null && !policies.some((p) => samePolicyDomain(p, candidate));
  const replace = (p: DomainPolicy, next: DomainPolicy) => onChange(policies.map((x) => (samePolicyDomain(x, p) ? next : x)));
  const commonRoom = policies.find(isCommonRoom);
  return (
    <div className={css.section} aria-label="Domains declared in this version">
      <p className={css.note}>
        Domains: a part of your life or {name}'s, declared here with who it may reach. Only a declared domain can be tagged, classified or annotated anywhere else; everywhere else picks from this list.
      </p>
      {/* The common room (kumbukumbu#97): what no domain names. Unwritten,
          it reaches every audience but the public ones; written here, its
          policy decides like any domain's. */}
      {!commonRoom && (
        <div className={css.formRow}>
          <span className={css.plain}>{COMMON_ROOM_DEFAULT}</span>
          <button type="button" className={css.secondary} onClick={() => onChange([...policies, { domain: COMMON_ROOM, default: 'allow', allow: [], deny: [] }])}>
            Write the common room's policy
          </button>
        </div>
      )}
      {policies.map((p) => (
        <div key={`${p.domain.person}/${p.domain.domain}`} className={css.formRow}>
          <span className={css.plain}>{policyWords(p, persons, name)}</span>
          <GrantAdder households={households} onAdd={(side, grant) => replace(p, { ...p, [side]: [...p[side], grant] })} />
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
// ("*" for every one of the kind). A household is picked by its name,
// never typed (kumbukumbu#102; the witness, 2026-11-21: "I had no way of
// knowing the house id"): the grant holds its slug, or its id while the
// house is unnamed, and either matches at delivery.
type Household = { id: string; slug: string | null };
function GrantAdder({ households, onAdd }: { households: Household[]; onAdd: (side: 'allow' | 'deny', grant: { kind: string; id: string }) => void }) {
  const [side, setSide] = useState<'allow' | 'deny'>('allow');
  const [kind, setKind] = useState<string>('household');
  const [gid, setGid] = useState('*');
  const housePick = kind === 'household';
  return (
    <>
      <select className={css.select} value={side} onChange={(e) => setSide(e.target.value as 'allow' | 'deny')} aria-label="Allow or deny">
        <option value="allow">allow</option>
        <option value="deny">deny</option>
      </select>
      <select className={css.select} value={kind} onChange={(e) => { setKind(e.target.value); setGid("*"); }} aria-label="Audience kind">
        {KINDS.map((k) => (
          <option key={k} value={k}>
            {k}
          </option>
        ))}
      </select>
      {housePick ? (
        <select className={css.select} value={gid} onChange={(e) => setGid(e.target.value)} aria-label="Which household">
          <option value="*">any household</option>
          {households.map((h) => (
            <option key={h.id} value={h.slug ?? h.id}>
              {h.slug ?? 'your household (unnamed)'}
            </option>
          ))}
        </select>
      ) : (
        <input className={css.input} value={gid} onChange={(e) => setGid(e.target.value)} aria-label="Audience id, * for any" />
      )}
      <button type="button" className={css.secondary} disabled={!gid.trim()} onClick={() => onAdd(side, { kind, id: gid.trim() })}>
        Add
      </button>
    </>
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
            {/* The whole version, not its prose alone (agathos-daimon#59): what it switches on and the domains it declares. */}
            <p className={css.note}>
              Switched on:{' '}
              {Object.entries(v.terms)
                .filter(([, on]) => on === true)
                .map(([k]) => k.replace(/_/g, ' '))
                .join(', ') || 'nothing beyond the defaults'}
            </p>
            {(() => {
              const policies = (Array.isArray(v.terms.domain_policies) ? v.terms.domain_policies : []) as DomainPolicy[];
              if (policies.length === 0) return <p className={css.note}>Domains: none declared.</p>;
              return (
                <ul className={css.note}>
                  {policies.map((p) => (
                    <li key={`${p.domain.person}/${p.domain.domain}`}>{a.persons ? policyWords(p, a.persons, name) : `${p.domain.domain}: ${p.default}`}</li>
                  ))}
                </ul>
              );
            })()}
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
