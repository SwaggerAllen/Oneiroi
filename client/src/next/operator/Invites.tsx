import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type InviteDefaults, type InviteRequest } from '../../api/client';
import { draftOf, skuOf, standing, termsLine, type InviteDraft } from './logic';
import { Card, Field, RevokeWithNote, SaidLine } from './parts';
import { useOp } from './useOp';
import * as css from './operator.css';

const KEY = ['operator', 'invites'];

/**
 * Invite codes (gaia#18): each a SKU (plan, list price, discount, days of
 * terms, uses, expiry) that grants a household its terms when redeemed.
 * Nothing is charged. A new code is shown once, here, in memory; the
 * server keeps only its hash.
 */
export function Invites() {
  const invites = useQuery({ queryKey: KEY, queryFn: api.invites });
  const op = useOp();
  const [issued, setIssued] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const list = invites.data?.invites ?? [];
  return (
    <>
      {invites.data && (
        <IssueForm
          key={JSON.stringify(invites.data.defaults)}
          defaults={invites.data.defaults}
          busy={op.busy}
          onIssue={(sku) =>
            op.run(async () => {
              const r = await api.issueInvite(sku);
              setIssued(r.code);
              setCopied(false);
              return 'Issued.';
            }, KEY)
          }
        />
      )}
      {issued && (
        <section className={css.card} aria-label="The new code">
          <h2 className={css.heading}>THE NEW CODE</h2>
          <p className={css.code}>{issued}</p>
          <p className={css.note}>Copy it now; it isn't shown again.</p>
          <div className={css.buttons}>
            <button
              type="button"
              className={css.button}
              onClick={() =>
                void navigator.clipboard
                  ?.writeText(issued)
                  .then(() => setCopied(true))
                  .catch(() => undefined)
              }
            >
              {copied ? 'Copied' : 'Copy'}
            </button>
            <button type="button" className={css.button} onClick={() => setIssued(null)}>
              Done
            </button>
          </div>
        </section>
      )}
      <Card title={`CODES · ${list.length}`} label="Codes issued">
        {invites.isError && <p className={css.refused}>The codes didn't load.</p>}
        {invites.data && list.length === 0 && <p className={css.note}>None issued.</p>}
        {list.map((i) => (
          <div key={i.id} className={css.row} data-gone={!!i.revoked_at}>
            <span className={css.stack}>
              <span>
                {i.note ?? 'A code'} · {termsLine(i)}
              </span>
              <span className={css.mono}>
                {standing(i)} · issued {i.issued_at.slice(0, 10)} · {i.expires_at ? `until ${i.expires_at.slice(0, 10)}` : 'no expiry'}
                {i.revoke_note ? ` · revoked: ${i.revoke_note}` : ''}
              </span>
            </span>
            {!i.revoked_at && (
              <RevokeWithNote what={i.note ? `the code “${i.note}”` : 'this code'} busy={op.busy} onRevoke={(note) => op.run(() => api.revokeInvite(i.id, note).then(() => 'Revoked.'), KEY)} />
            )}
          </div>
        ))}
        <SaidLine said={op.said} />
      </Card>
    </>
  );
}

function IssueForm({ defaults, busy, onIssue }: { defaults: InviteDefaults; busy: boolean; onIssue: (sku: InviteRequest) => Promise<boolean> }) {
  const [draft, setDraft] = useState<InviteDraft>(() => draftOf(defaults));
  const set = (k: keyof InviteDraft) => (e: { target: { value: string } }) => setDraft((d) => ({ ...d, [k]: e.target.value }));
  const sku = skuOf(draft);
  return (
    <section className={css.card} aria-label="Issue a code">
      <h2 className={css.heading}>ISSUE A CODE</h2>
      <p className={css.note}>Each code grants a household its terms when it's redeemed. Nothing is charged. The defaults are the alpha's free code.</p>
      <form
        className={css.form}
        onSubmit={(e) => {
          e.preventDefault();
          if (sku) void onIssue(sku).then((ok) => ok && setDraft(draftOf(defaults)));
        }}
      >
        <Field label="Who it's for, or why (required)" value={draft.note} onChange={set('note')} />
        <div className={css.grid}>
          <Field label="Plan" value={draft.plan} onChange={set('plan')} />
          <Field label="List price ($)" inputMode="decimal" value={draft.price} onChange={set('price')} />
          <Field label="Discount (%)" inputMode="numeric" value={draft.discount} onChange={set('discount')} />
          <Field label="Days of terms" inputMode="numeric" value={draft.days} onChange={set('days')} />
          <Field label="Uses" inputMode="numeric" value={draft.uses} onChange={set('uses')} />
          <Field label="Expires (optional)" type="date" value={draft.expires} onChange={set('expires')} />
        </div>
        <div className={css.buttons}>
          <button type="submit" className={css.primary} disabled={busy || !sku}>
            Issue a code
          </button>
        </div>
      </form>
    </section>
  );
}
