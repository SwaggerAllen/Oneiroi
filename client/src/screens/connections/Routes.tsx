import { useState } from 'react';
import type { ProfileEntry, RouteDefinition, RouteEntry, RoutesData } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export interface RoutesProps {
  name: string;
  data: RoutesData;
  busy?: boolean;
  said?: string | null;
  onDefine?: (definition: RouteDefinition) => void;
  onAsk?: (key: string, note: string) => void;
  onSetProfile?: (profile: { key: string; label?: string; origin?: string; signed_in_as?: string; note?: string }) => void;
  onRevoke?: (key: string, note: string) => void;
  onRestore?: (key: string, note: string) => void;
}

const muted = { margin: 0, fontSize: 13, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', alignItems: 'center' } as const;
const list = { margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' } as const;
const routeKey = /^[a-z][a-z0-9-]{1,39}$/;
const origin = /^https:\/\/[a-z0-9.-]+(:[0-9]{1,5})?$/;

function routeLine(r: RouteEntry): string {
  const dir = r.direction === 'source' ? `in, as ${r.kind}` : `out, from ${r.kind}, at your approval`;
  return `${dir} · through ${r.profile} · ${r.cadence.replace('_', ' ')}`;
}

function profileLine(p: ProfileEntry): string {
  const where = p.origin ?? 'signed in nowhere';
  const who = p.signed_in_as ? ` · signed in as ${p.signed_in_as}` : '';
  const reach = p.connector ? ` · through the ${p.connector} connector` : p.sites.length > 0 ? ` · reaches ${p.sites.join(', ')}` : '';
  return `${where}${who}${reach}`;
}

// Routes and profiles (xenia#19): every way into or out of the house,
// each bound to one profile. A profile is a signed-in context on one
// origin; yours to make, revoke and restore, and never a credential
// here. A revoked profile's routes stay listed, unable, and say why.
// A route of hers is a source on request; its prompt is what it reads
// for and nothing more.
export function Routes({ name, data, busy = false, said = null, onDefine, onAsk, onSetProfile, onRevoke, onRestore }: RoutesProps) {
  const [note, setNote] = useState('');
  const [key, setKey] = useState('');
  const [prompt, setPrompt] = useState('');
  const [profile, setProfile] = useState('');
  const [kind, setKind] = useState('');
  const [pKey, setPKey] = useState('');
  const [pOrigin, setPOrigin] = useState('');
  const [pAs, setPAs] = useState('');
  const noted = note.trim() !== '' && !busy;
  const standing = data.profiles.filter((p) => !p.revoked);
  const builtIn = data.routes.filter((r) => r.built_in);
  const hers = data.routes.filter((r) => !r.built_in);
  const routeOk = routeKey.test(key) && !builtIn.some((r) => r.key === key) && prompt.trim() !== '' && prompt.length <= 4000 && profile !== '' && kind !== '';
  const profileOk = routeKey.test(pKey) && origin.test(pOrigin) && !data.profiles.some((p) => p.seeded && p.key === pKey);
  return (
    <Card title="Routes and profiles">
      <p style={muted}>
        Every way into or out of {name}'s house, each through one profile. A profile is a browser signed in on one site, on the reader's machine; nothing here holds its password.
      </p>
      <Field label="A note for the next change" value={note} onChange={(e) => setNote(e.target.value)} />
      <section aria-label="Profiles" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
        <strong style={{ fontSize: 15 }}>Profiles</strong>
        <ul aria-label="Profiles" style={list}>
          {data.profiles.map((p) => (
            <li key={p.key} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
              <span>
                <strong>{p.label}</strong> <span style={{ color: 'var(--ink-muted)' }}>({p.key})</span>
                {p.revoked ? ' · revoked' : ''}
              </span>
              <span style={muted}>{profileLine(p)}</span>
              <span style={muted}>{p.routes.length > 0 ? `Routes: ${p.routes.join(', ')}` : 'No route uses it.'}</span>
              <div style={row}>
                {p.revoked ? (
                  <Button variant="quiet" disabled={!noted} onClick={() => onRestore?.(p.key, note.trim())}>
                    Restore
                  </Button>
                ) : (
                  <Button variant="quiet" disabled={!noted} onClick={() => onRevoke?.(p.key, note.trim())}>
                    Revoke
                  </Button>
                )}
              </div>
            </li>
          ))}
        </ul>
        <form
          aria-label="Make a profile"
          onSubmit={(e) => {
            e.preventDefault();
            if (!profileOk || busy) return;
            onSetProfile?.({ key: pKey, origin: pOrigin, signed_in_as: pAs.trim() || undefined, note: note.trim() || undefined });
            setPKey('');
            setPOrigin('');
            setPAs('');
          }}
          style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
        >
          <p style={muted}>A profile reaches exactly one site. Sign it in on the reader's machine with reader.sh login and its name.</p>
          <Field label="Profile name" value={pKey} onChange={(e) => setPKey(e.target.value.trim())} />
          <Field label="Its one site (https://host)" value={pOrigin} onChange={(e) => setPOrigin(e.target.value.trim())} />
          <Field label="Signed in as" value={pAs} onChange={(e) => setPAs(e.target.value)} />
          <div style={row}>
            <Button type="submit" variant="primary" disabled={!profileOk || busy}>
              Make the profile
            </Button>
          </div>
        </form>
      </section>
      <section aria-label="Routes" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
        <strong style={{ fontSize: 15 }}>Routes</strong>
        <ul aria-label="Routes" style={list}>
          {[...builtIn, ...hers].map((r) => (
            <li key={r.key} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
              <span>
                <strong>{r.label}</strong> <span style={{ color: 'var(--ink-muted)' }}>({r.key})</span>
                {r.built_in ? '' : ` · ${name}'s`}
              </span>
              <span style={muted}>{routeLine(r)}</span>
              {r.state === 'unable' ? <span style={{ ...muted, color: 'var(--ink)' }}>Unable to fire: {r.why}</span> : null}
              {r.prompt ? <span style={muted}>Reads for: {r.prompt}</span> : null}
              {!r.built_in && r.state === 'ready' ? (
                <div style={row}>
                  <Button variant="quiet" disabled={busy} onClick={() => onAsk?.(r.key, note.trim())}>
                    Ask a run
                  </Button>
                </div>
              ) : null}
            </li>
          ))}
        </ul>
        {data.runs.length > 0 ? (
          <ul aria-label="Runs" style={list}>
            {data.runs.slice(0, 10).map((run) => (
              <li key={run.number} style={muted}>
                #{run.number} {run.key}: {run.state}
                {run.path ? `, as ${run.path}` : ''}
                {run.reason ? ` (${run.reason})` : ''}
              </li>
            ))}
          </ul>
        ) : null}
        <form
          aria-label="Define a route"
          onSubmit={(e) => {
            e.preventDefault();
            if (!routeOk || busy) return;
            onDefine?.({ key, prompt: prompt.trim(), profile, kind, note: note.trim() || undefined });
            setKey('');
            setPrompt('');
          }}
          style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
        >
          <strong style={{ fontSize: 15 }}>A route of {name}'s</strong>
          <p style={muted}>A reading the reader does on request, through a profile that stands, landing as documents of a kind she writes. What it reads for is only that: it never chooses the profile, the sites or where it lands.</p>
          <Field label="Route name" value={key} onChange={(e) => setKey(e.target.value.trim())} />
          <Field label="What it reads for" value={prompt} onChange={(e) => setPrompt(e.target.value)} />
          <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
            <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Through</span>
            <select value={profile} onChange={(e) => setProfile(e.target.value)}>
              <option value="">Choose a profile</option>
              {standing.map((p) => (
                <option key={p.key} value={p.key}>
                  {p.label}
                </option>
              ))}
            </select>
          </label>
          <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
            <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Lands as</span>
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="">Choose a kind</option>
              {data.landing.map((k) => (
                <option key={k} value={k}>
                  {k}
                </option>
              ))}
            </select>
          </label>
          <div style={row}>
            <Button type="submit" variant="primary" disabled={!routeOk || busy}>
              Define the route
            </Button>
          </div>
        </form>
      </section>
      {said ? (
        <p role="status" style={{ margin: 0, fontSize: 15 }}>
          {said}
        </p>
      ) : null}
    </Card>
  );
}
