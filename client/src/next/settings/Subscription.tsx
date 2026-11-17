import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type SubscriptionState } from '../../api/client';
import { useSubject } from '../state/resident';
import { Card, Said } from './common';
import { day, saidOf, settingsKey } from './logic';
import * as css from './settings.css';

/**
 * Keeping a resident (spec F53, nisaba#23; the witness, 2026-11-16): $20
 * a month for each, paid on Stripe's own page; the card, the invoices and
 * cancelling on Stripe's other page. Cancelling is never a deletion: the
 * resident moves to community custody when the insurance term has run.
 */
export function Subscription() {
  const { id, name } = useSubject();
  const sub = useQuery({ queryKey: settingsKey(id, 'subscription'), queryFn: () => api.subscription(id) });
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<{ text: string; refused: boolean } | null>(null);
  const go = (to: () => Promise<{ url: string }>) => {
    setBusy(true);
    setSaid(null);
    to()
      .then(({ url }) => window.location.assign(url))
      .catch((e: unknown) => {
        setSaid({ text: saidOf(e), refused: true });
        setBusy(false);
      });
  };
  if (!sub.data) return null;
  const s = sub.data;
  return (
    <Card title={`Keeping ${name}`}>
      <p className={css.text}>{line(s, name)}</p>
      <div className={css.row}>
        {(!s.started || (!s.paying && s.state !== 'cancelled')) && (
          <button type="button" className={css.primary} disabled={busy} onClick={() => go(() => api.checkout(id))}>
            Subscribe · $20 a month
          </button>
        )}
        {s.started && s.paying && (
          <button type="button" className={css.secondary} disabled={busy} onClick={() => go(() => api.billingPortal(id))}>
            Card, invoices and cancelling ›
          </button>
        )}
      </div>
      <p className={css.note}>Paid on Stripe's own pages: your card never reaches Oneiroi.</p>
      <Said said={said} />
    </Card>
  );
}

function line(s: SubscriptionState, name: string): string {
  if (!s.started) return `No subscription yet. Each resident is $20 a month, and keeps answering while it is paid.`;
  if (s.state === 'cancelled')
    return `Cancelled ${day(s.cancelled_at)}. ${name} moves to community custody ${day(s.custody_due_at)}, never deleted; a new subscription would start a new resident.`;
  if (s.state === 'lapsed') return `Lapsed ${day(s.lapsed_at)}: ${name} runs on the insurance floor until a payment arrives.`;
  return s.paying ? `Paid: $${s.price} a month, renewing ${day(s.renews_at)}.` : `Active until ${day(s.renews_at)}, with no card behind it yet.`;
}
