// The operator shell's logic, apart from its components (screens/next-operator.md).
import type { Invite, InviteDefaults, InviteRequest, PlatformRole } from '../../api/client';

export const dollars = (nanos: number) => `$${(nanos / 1_000_000_000).toFixed(2).replace(/\.00$/, '')}`;

/** Where a code stands: revoked, expired, spent, or how many of its uses are taken. */
export function standing(i: Invite, now: Date = new Date()): string {
  if (i.revoked_at) return 'revoked';
  if (i.expires_at && new Date(i.expires_at) <= now) return 'expired';
  if (i.redeemed >= i.uses) return 'spent';
  return `${i.redeemed} of ${i.uses} used`;
}

/** A code's terms in a line: plan, price (and the discount off the list), days. */
export function termsLine(i: Invite): string {
  const off = i.discount_pct > 0 ? ` (${dollars(i.list_price_nanos)} less ${i.discount_pct}%)` : '';
  return `${i.plan}, ${dollars(i.price_nanos)}${off} for ${i.term_days} days`;
}

export interface InviteDraft {
  note: string;
  plan: string;
  price: string;
  discount: string;
  days: string;
  uses: string;
  expires: string;
}

/** The issue form, filled from the server's defaults (the alpha's free code). */
export function draftOf(d: InviteDefaults): InviteDraft {
  return {
    note: '',
    plan: d.plan,
    price: String(d.price_nanos / 1_000_000_000),
    discount: String(d.discount_pct),
    days: String(d.term_days),
    uses: String(d.uses),
    expires: d.expires_at ? d.expires_at.slice(0, 10) : '',
  };
}

/** The request a draft makes, or null while it can't be sent (no note, or a number that isn't one). */
export function skuOf(d: InviteDraft): InviteRequest | null {
  const note = d.note.trim();
  const plan = d.plan.trim();
  const price = Number(d.price);
  const discount = Number(d.discount);
  const days = Number(d.days);
  const uses = Number(d.uses);
  if (!note || !plan) return null;
  if (![price, discount, days, uses].every((n) => Number.isFinite(n) && n >= 0)) return null;
  if (d.price.trim() === '' || d.discount.trim() === '' || d.days.trim() === '' || d.uses.trim() === '') return null;
  const sku: InviteRequest = {
    note,
    plan,
    price_cents: Math.round(price * 100),
    discount_pct: discount,
    term_days: days,
    uses,
  };
  if (d.expires) sku.expires_at = new Date(d.expires).toISOString();
  return sku;
}

export const REPORT_STATUSES = ['new', 'in_work', 'resolved', 'closed'] as const;
export const statusWord = (s: string) => s.replace('_', ' ');

export const ROLE_NAMES: Record<PlatformRole, string> = {
  super_admin: 'Super admin',
  admin: 'Admin',
};
