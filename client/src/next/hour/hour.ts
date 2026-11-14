// The public hour's words and figures (apsu#29), pure so they are tested
// apart from the page.
import type { Few } from '../../api/client';

/** A millisecond figure as a reader takes it: 40 ms, 1.2 s, 60 s+ for the top bucket. */
export function ms(v: number | null): string {
  if (v === null) return '—';
  if (v >= 60_000) return '60 s+';
  if (v >= 1_000) return `${(v / 1_000).toFixed(v >= 10_000 ? 0 : 1)} s`;
  return `${v} ms`;
}

/** A count, or "few" for one under five, said plainly. */
export const count = (v: Few) => (v === 'few' ? 'few' : String(v));

/** A unit of work's name in plain words: the route without its method's noise, a worker by its last name. */
export function unitName(kind: string, name: string): string {
  if (kind === 'job') return name.split('.').pop() ?? name;
  return name;
}

/** The trend's bar heights, 0 to 1, by units; "few" draws as a sliver. */
export function bars(trend: { units: Few }[]): number[] {
  const nums = trend.map((b) => (b.units === 'few' ? 2 : b.units));
  const top = Math.max(1, ...nums);
  return nums.map((n) => n / top);
}
