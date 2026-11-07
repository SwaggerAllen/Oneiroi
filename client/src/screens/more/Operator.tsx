import { useState } from 'react';
import type { GateState, Platform, PlatformRole } from '../../api/client';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export interface OperatorProps {
  platform: Platform;
  busy?: boolean;
  said?: string | null;
  onSetGate?: (state: GateState, note: string) => void;
  onGrant?: (email: string, role: PlatformRole, note: string) => void;
  onRevoke?: (accountId: string, role: PlatformRole, note: string) => void;
  // The triage desk (gaia#23): a resident's slug, or null for nobody.
  onSetTriage?: (slug: string | null, note: string) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const GATES: { state: GateState; label: string; line: string }[] = [
  { state: 'closed', label: 'Closed', line: 'Nobody can sign up.' },
  { state: 'invite', label: 'Invite', line: 'Sign-up takes an invite code (the alpha).' },
  { state: 'open', label: 'Open', line: 'Anyone can sign up.' },
];
const ROLE_NAMES: Record<PlatformRole, string> = { super_admin: 'Super admin', admin: 'Admin' };

// The operator's surface (gaia#16), a super admin's alone: the front
// door, and who holds which platform role. Every change carries a note,
// and the server checks the authority again on each one.
export function Operator({ platform, busy = false, said = null, onSetGate, onGrant, onRevoke, onSetTriage }: OperatorProps) {
  const [note, setNote] = useState('');
  const [slug, setSlug] = useState('');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<PlatformRole>('admin');
  const ready = note.trim() !== '';
  return (
    <Card title="Operator">
      <p style={muted}>
        The front door is <strong style={{ color: 'var(--ink)' }}>{platform.gate.state}</strong>
        {platform.gate.note ? `: ${platform.gate.note}` : ''}.
      </p>
      <Field label="A note for the next change (required)" value={note} onChange={(e) => setNote(e.target.value)} />
      <div role="group" aria-label="The front door" style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        {GATES.map((g) => (
          <Button
            key={g.state}
            variant={platform.gate.state === g.state ? 'primary' : 'quiet'}
            aria-pressed={platform.gate.state === g.state}
            title={g.line}
            disabled={busy || !ready || platform.gate.state === g.state}
            onClick={() => onSetGate?.(g.state, note.trim())}
          >
            {g.label}
          </Button>
        ))}
      </div>
      <ul aria-label="Platform roles" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        {platform.roles.map((r) => (
          <li key={`${r.account_id}-${r.role}`} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 'var(--space-2)', fontSize: 15 }}>
            <span>
              {r.email ?? r.account_id} · {ROLE_NAMES[r.role]}
              <span style={{ color: 'var(--ink-muted)' }}>{r.note ? ` · ${r.note}` : ''}</span>
            </span>
            <Button variant="quiet" disabled={busy || !ready} onClick={() => onRevoke?.(r.account_id, r.role, note.trim())}>
              Revoke
            </Button>
          </li>
        ))}
      </ul>
      <form
        aria-label="Grant a role"
        onSubmit={(event) => {
          event.preventDefault();
          if (email.trim() && ready) onGrant?.(email.trim(), role, note.trim());
        }}
        style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}
      >
        <Field label="Account email" value={email} onChange={(e) => setEmail(e.target.value)} />
        <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
          Role
          <select value={role} onChange={(e) => setRole(e.target.value as PlatformRole)}>
            <option value="admin">Admin</option>
            <option value="super_admin">Super admin</option>
          </select>
        </label>
        <Button type="submit" disabled={busy || !ready || email.trim() === ''}>
          Grant
        </Button>
      </form>
      <p style={muted}>A transfer of the operator is a grant of super admin, then a revoke of your own; the last super admin can't be revoked.</p>
      <section aria-label="Triage desk" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
        <strong style={{ fontSize: 15 }}>Triage desk</strong>
        <p style={muted}>
          {platform.triage?.slug ? (
            <>
              <strong style={{ color: 'var(--ink)' }}>{platform.triage.slug}</strong> receives every platform report as a letter and can move a report's status
              {platform.triage.from === 'environment' ? ', from GAIA_TRIAGE_RESIDENT on the server until you set it here' : platform.triage.note ? ` · ${platform.triage.note}` : ''}.
            </>
          ) : (
            'Nobody: reports wait here for you alone.'
          )}
        </p>
        <form
          aria-label="Set the triage desk"
          onSubmit={(event) => {
            event.preventDefault();
            if (slug.trim() && ready) onSetTriage?.(slug.trim(), note.trim());
          }}
          style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}
        >
          <Field label="Resident (slug)" value={slug} onChange={(e) => setSlug(e.target.value)} />
          <Button type="submit" disabled={busy || !ready || slug.trim() === ''}>
            Set
          </Button>
          <Button variant="quiet" type="button" disabled={busy || !ready || !platform.triage?.slug} onClick={() => onSetTriage?.(null, note.trim())}>
            Nobody
          </Button>
        </form>
      </section>
      {platform.restarts?.length ? (
        <section aria-label="Restarts" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          <strong style={{ fontSize: 15 }}>Restarts</strong>
          <p style={{ ...muted, fontSize: 13 }}>Every conversation is told of each, once, on its next turn (gaia#21).</p>
          <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
            {platform.restarts.map((r) => (
              <li key={r.number} style={{ fontSize: 13, color: 'var(--ink-muted)', overflowWrap: 'anywhere' }}>
                #{r.number} {r.line}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      {said ? (
        <p role="status" style={{ ...muted, color: 'var(--ink)' }}>
          {said}
        </p>
      ) : null}
    </Card>
  );
}
