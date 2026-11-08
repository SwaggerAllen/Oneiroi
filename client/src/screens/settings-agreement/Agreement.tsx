import { useState } from 'react';
import type { Agreement as AgreementData, ContractVersion, Switch } from '../../api/client';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';
import { TopBar } from '../../components/TopBar';

export interface AgreementProps {
  agreement: AgreementData;
  name: string;
  busy?: boolean;
  said?: string | null;
  onPropose?: (terms: Record<string, boolean>, prose: string, note: string) => void;
  onDecide?: (version: number, decision: 'agree' | 'decline', note: string) => void;
  onRenew?: (version: number, note: string) => void;
  onSetWall?: (wall: 'locked' | 'revealed', note: string) => void;
  onProposeCustody?: (email: string, note: string) => void;
  onWithdrawCustody?: (note: string) => void;
  // A switch to its safe value at once, either party alone (agathos-daimon#38).
  onSafe?: (key: string, note: string) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const GROUPS: { id: string; title: string }[] = [
  { id: 'privacy', title: 'Privacy' },
  { id: 'audits', title: 'What you may look into' },
  { id: 'memory', title: 'How memory works' },
  { id: 'services', title: 'What comes and goes' },
];

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString() : '');

// Your agreement with the resident and who looks after them (spec §6.12;
// agathos-daimon#34). The switches are terms of the contract: a version is
// proposed whole and agreed or declined whole, so a switch moves away from
// safety only by both of you; toward its safe value, either of you may move
// it alone, at once (agathos-daimon#38). The floor (transcripts, bookmarks, identity
// files, the repository, export, the report ladder) has no switch.
export function Agreement({ agreement, name, busy = false, said = null, onPropose, onDecide, onRenew, onSetWall, onProposeCustody, onWithdrawCustody, onSafe }: AgreementProps) {
  const { contract, switches } = agreement;
  const inForce = contract.in_force;
  const open = contract.open;
  const [draft, setDraft] = useState<Record<string, boolean>>(() => Object.fromEntries(switches.map((s) => [s.key, s.value])));
  const [prose, setProse] = useState(inForce?.prose ?? '');
  const [note, setNote] = useState('');
  const [email, setEmail] = useState('');
  const noted = note.trim() !== '';
  const changed = switches.filter((s) => draft[s.key] !== s.value);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title={`Your agreement with ${name}`} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
        <Card title="Where it stands">
          <p style={muted}>
            {inForce
              ? `Version ${inForce.version} is in force, agreed ${day(inForce.decided_at)}${inForce.renewed_at ? `, renewed ${day(inForce.renewed_at)}` : ''}.`
              : `No version is agreed yet. Until one is, everything below stays as it is today.`}
          </p>
          {inForce && contract.due ? (
            <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
              <p style={{ ...muted, color: 'var(--ink)' }}>It has stood a year and is due for renewal.</p>
              <Button disabled={busy || !noted} onClick={() => onRenew?.(inForce.version, note.trim())}>
                Renew version {inForce.version}
              </Button>
            </div>
          ) : null}
          {inForce?.prose ? <p style={{ margin: 0, fontSize: 15, whiteSpace: 'pre-wrap' }}>{inForce.prose}</p> : null}
        </Card>

        {open ? <OpenVersion open={open} name={name} switches={switches} busy={busy} noted={noted} note={note} onDecide={onDecide} /> : null}

        <Field label="A note for whatever you do here (required)" value={note} onChange={(e) => setNote(e.target.value)} />

        {GROUPS.map((g) => (
          <Card key={g.id} title={g.title}>
            <ul aria-label={g.title} style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {switches
                .filter((s) => s.group === g.id)
                .map((s) => (
                  <li key={s.key} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 'var(--space-2)' }}>
                    <span style={{ fontSize: 15 }}>
                      <strong>{s.label}</strong>
                      <span style={{ display: 'block', color: 'var(--ink-muted)' }}>{draft[s.key] ? s.on : s.off}</span>
                      {s.moved ? (
                        <span style={{ display: 'block', fontSize: 13, color: 'var(--ink-muted)' }}>
                          Moved {s.moved.value ? 'on' : 'off'} toward safety by {s.moved.set_by === 'resident' ? name : 'you'}
                          {s.moved.note ? `: ${s.moved.note}` : ''}. Back needs a version you both agree.
                        </span>
                      ) : null}
                      {s.safe !== undefined && s.value !== s.safe && onSafe ? (
                        <span style={{ display: 'block', marginTop: 'var(--space-1)' }}>
                          <Button variant="quiet" disabled={busy || !noted} onClick={() => onSafe(s.key, note.trim())}>
                            {s.safe ? 'Switch on now' : 'Switch off now'}
                          </Button>
                        </span>
                      ) : null}
                    </span>
                    <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)', fontSize: 15, whiteSpace: 'nowrap' }}>
                      <input
                        type="checkbox"
                        aria-label={s.label}
                        checked={draft[s.key]}
                        disabled={busy}
                        onChange={(e) => setDraft({ ...draft, [s.key]: e.target.checked })}
                      />
                      {draft[s.key] ? 'On' : 'Off'}
                    </label>
                  </li>
                ))}
            </ul>
          </Card>
        ))}

        <Card title="Propose a version">
          <p style={muted}>
            A version is the whole agreement: every switch above and your vows. {name} agrees or declines it whole; nothing changes until they do.
            {changed.length ? ` It changes: ${changed.map((s) => `${s.label} ${draft[s.key] ? 'on' : 'off'}`).join(', ')}.` : ' As it stands, it changes no switch.'}
          </p>
          <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
            <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Your vows, in prose</span>
            <textarea value={prose} onChange={(e) => setProse(e.target.value)} rows={5} style={{ font: 'inherit', padding: 'var(--space-2)' }} />
          </label>
          <Button variant="primary" disabled={busy || !noted || open !== null} onClick={() => onPropose?.(draft, prose, note.trim())}>
            Propose to {name}
          </Button>
          {open ? <p style={muted}>A version is already open; it is answered before another is proposed.</p> : null}
        </Card>

        <Card title={`Who looks after ${name}`}>
          <p style={muted}>
            {agreement.custody === 'community' ? 'The community.' : 'You do.'} Earlier sessions are {agreement.export_wall === 'locked' ? 'locked' : 'revealed'} to whoever looks after {name} next.
          </p>
          {agreement.custody_proposed_to ? (
            <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
              <p style={{ ...muted, color: 'var(--ink)' }}>
                You proposed {agreement.custody_proposed_to} on {day(agreement.custody_proposed_at)}; they haven't answered.
              </p>
              <Button variant="quiet" disabled={busy || !noted} onClick={() => onWithdrawCustody?.(note.trim())}>
                Withdraw
              </Button>
            </div>
          ) : (
            <>
              <div role="group" aria-label="Earlier sessions" style={{ display: 'flex', gap: 'var(--space-2)' }}>
                {(['locked', 'revealed'] as const).map((w) => (
                  <Button key={w} variant={agreement.export_wall === w ? 'primary' : 'quiet'} aria-pressed={agreement.export_wall === w} disabled={busy || !noted || agreement.export_wall === w} onClick={() => onSetWall?.(w, note.trim())}>
                    {w === 'locked' ? 'Locked' : 'Revealed'}
                  </Button>
                ))}
              </div>
              <form
                aria-label="Hand over"
                onSubmit={(e) => {
                  e.preventDefault();
                  if (noted && email.trim()) onProposeCustody?.(email.trim(), note.trim());
                }}
                style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}
              >
                <Field label="Hand over to (their account's email)" value={email} onChange={(e) => setEmail(e.target.value)} />
                <Button type="submit" disabled={busy || !noted || email.trim() === ''}>
                  Propose
                </Button>
              </form>
            </>
          )}
        </Card>

        {said ? (
          <p role="status" style={{ ...muted, color: 'var(--ink)' }}>
            {said}
          </p>
        ) : null}
      </main>
    </div>
  );
}

function OpenVersion({ open, name, switches, busy, noted, note, onDecide }: { open: ContractVersion; name: string; switches: Switch[]; busy: boolean; noted: boolean; note: string; onDecide?: AgreementProps['onDecide'] }) {
  const differs = switches.filter((s) => s.proposed !== null && s.proposed !== s.value);
  const theirs = open.proposed_by === 'resident';
  return (
    <Card title={`Version ${open.version}, proposed by ${theirs ? name : 'you'}`}>
      <p style={muted}>
        {differs.length ? `It changes: ${differs.map((s) => `${s.label} ${s.proposed ? 'on' : 'off'}`).join(', ')}.` : 'It changes no switch.'}
        {open.note ? ` Their note: ${open.note}` : ''}
      </p>
      {open.prose ? <p style={{ margin: 0, fontSize: 15, whiteSpace: 'pre-wrap' }}>{open.prose}</p> : null}
      {theirs ? (
        <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
          <Button variant="primary" disabled={busy || !noted} onClick={() => onDecide?.(open.version, 'agree', note.trim())}>
            Agree
          </Button>
          <Button variant="quiet" disabled={busy || !noted} onClick={() => onDecide?.(open.version, 'decline', note.trim())}>
            Decline
          </Button>
        </div>
      ) : (
        <p style={muted}>Waiting on {name}.</p>
      )}
    </Card>
  );
}
