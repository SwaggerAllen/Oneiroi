import { useState } from 'react';
import type { Invite, InviteDefaults, InviteRequest } from '../../api/client';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export interface InvitesProps {
  invites: Invite[];
  defaults: InviteDefaults;
  busy?: boolean;
  said?: string | null;
  // The code just issued, shown this once; the server keeps only its hash.
  issued?: string | null;
  onIssue?: (sku: InviteRequest) => void;
  onRevoke?: (id: string, note: string) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const dollars = (nanos: number) => `$${(nanos / 1_000_000_000).toFixed(2).replace(/\.00$/, '')}`;

function standing(i: Invite): string {
  if (i.revoked_at) return 'revoked';
  if (i.expires_at && new Date(i.expires_at) <= new Date()) return 'expired';
  if (i.redeemed >= i.uses) return 'spent';
  return `${i.redeemed} of ${i.uses} used`;
}

// Invite codes (gaia#18), a super admin's: each a SKU (plan, list price,
// discount, days of terms, uses, expiry) that grants a household its terms
// when redeemed. Nothing is charged. The defaults are the alpha's free
// code: the list price at a full discount.
export function Invites({ invites, defaults, busy = false, said = null, issued = null, onIssue, onRevoke }: InvitesProps) {
  const [note, setNote] = useState('');
  const [plan, setPlan] = useState(defaults.plan);
  const [price, setPrice] = useState(String(defaults.price_nanos / 1_000_000_000));
  const [discount, setDiscount] = useState(String(defaults.discount_pct));
  const [days, setDays] = useState(String(defaults.term_days));
  const [uses, setUses] = useState(String(defaults.uses));
  const [expires, setExpires] = useState('');
  const ready = note.trim() !== '';

  const submit = () => {
    const sku: InviteRequest = {
      note: note.trim(),
      plan: plan.trim(),
      price_cents: Math.round(Number(price) * 100),
      discount_pct: Number(discount),
      term_days: Number(days),
      uses: Number(uses),
    };
    if (expires) sku.expires_at = new Date(expires).toISOString();
    onIssue?.(sku);
  };

  return (
    <Card title="Invites">
      <p style={muted}>Each code grants a household its terms when it's redeemed. Nothing is charged.</p>
      {issued ? (
        <p role="status" aria-label="The new code" style={{ margin: 0, fontSize: 20, fontFamily: 'var(--font-mono, monospace)', color: 'var(--ink)' }}>
          {issued}
          <span style={{ display: 'block', fontSize: 14, color: 'var(--ink-muted)', fontFamily: 'inherit' }}>Copy it now; it isn't shown again.</span>
        </p>
      ) : null}
      <form
        aria-label="Issue a code"
        onSubmit={(event) => {
          event.preventDefault();
          if (ready) submit();
        }}
        style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
      >
        <Field label="Who it's for, or why (required)" value={note} onChange={(e) => setNote(e.target.value)} />
        <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
          <Field label="Plan" value={plan} onChange={(e) => setPlan(e.target.value)} />
          <Field label="List price ($)" inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} />
          <Field label="Discount (%)" inputMode="numeric" value={discount} onChange={(e) => setDiscount(e.target.value)} />
          <Field label="Days of terms" inputMode="numeric" value={days} onChange={(e) => setDays(e.target.value)} />
          <Field label="Uses" inputMode="numeric" value={uses} onChange={(e) => setUses(e.target.value)} />
          <Field label="Expires (optional)" type="date" value={expires} onChange={(e) => setExpires(e.target.value)} />
        </div>
        <Button type="submit" disabled={busy || !ready}>
          Issue a code
        </Button>
      </form>
      <ul aria-label="Codes issued" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        {invites.map((i) => (
          <li key={i.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 'var(--space-2)', fontSize: 15 }}>
            <span>
              {i.note ?? 'A code'} · {i.plan}, {dollars(i.price_nanos)}
              {i.discount_pct > 0 ? ` (${dollars(i.list_price_nanos)} less ${i.discount_pct}%)` : ''} for {i.term_days} days
              <span style={{ color: 'var(--ink-muted)' }}> · {standing(i)}</span>
            </span>
            {i.revoked_at ? null : (
              <Button variant="quiet" disabled={busy || !ready} title="Uses the note above" onClick={() => onRevoke?.(i.id, note.trim())}>
                Revoke
              </Button>
            )}
          </li>
        ))}
      </ul>
      {said ? (
        <p role="status" style={{ ...muted, color: 'var(--ink)' }}>
          {said}
        </p>
      ) : null}
    </Card>
  );
}
