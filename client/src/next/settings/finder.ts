// The catalog's search and filters (screen:next-settings, the witness,
// 2026-11-26: too big to navigate by scrolling). The whole catalog is
// one read; finding in it is the client's.
import type { CatalogModel } from '../../api/types';

export type CatalogSort = 'cheapest' | 'monthly' | 'dearest' | 'context' | 'measured' | 'name';

export interface CatalogFilter {
  /** Words, each matched anywhere in the slug, the name or the blurb. */
  query: string;
  /** A provider, the slug before its slash; '' for every provider. */
  provider: string;
  /** Only models that take tool calls (the only ones she can run on). */
  tools: boolean;
  /** Only models inside her succession's envelope, when it has one. */
  envelope: boolean;
  /** Only models whose tool calls Oneiroi has measured. */
  measured: boolean;
  /** At most this many dollars per million output tokens; null for no cap. */
  maxOutput: number | null;
  /** At least this many tokens of context; null for no floor. */
  minContext: number | null;
  sort: CatalogSort;
}

export const NO_FILTER: CatalogFilter = {
  query: '',
  provider: '',
  tools: true,
  envelope: false,
  measured: false,
  maxOutput: null,
  minContext: null,
  sort: 'cheapest',
};

export type Envelope = { input_per_million: number; output_per_million: number } | null;

export type Pace = { input_per_day: number; output_per_day: number } | null;

export const provider = (m: CatalogModel) => m.model.split('/')[0];

/** A month of her pace at a model's list prices, in dollars: the daily average × 30 (nisaba#25). */
export const monthly = (m: Pick<CatalogModel, 'input_per_million' | 'output_per_million'>, pace: NonNullable<Pace>) =>
  ((pace.input_per_day * m.input_per_million + pace.output_per_day * m.output_per_million) * 30) / 1_000_000;

/** The providers in the catalog, most models first, then by name. */
export function providers(models: CatalogModel[]): { name: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const m of models) counts.set(provider(m), (counts.get(provider(m)) ?? 0) + 1);
  return [...counts.entries()].map(([name, count]) => ({ name, count })).sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

export const inside = (m: CatalogModel, env: Envelope) => !env || (m.input_per_million <= env.input_per_million && m.output_per_million <= env.output_per_million);

/** The share of its measured tool calls that were well formed; null when none were measured. */
export const wellFormed = (m: CatalogModel) => (m.tool_calls ? (m.tool_calls - m.tool_calls_failed) / m.tool_calls : null);

function matches(m: CatalogModel, words: string[]): boolean {
  const hay = `${m.model} ${m.name ?? ''} ${m.description ?? ''}`.toLowerCase();
  return words.every((w) => hay.includes(w));
}

const order = (pace: Pace): Record<CatalogSort, (a: CatalogModel, b: CatalogModel) => number> => ({
  // Without her pace, a month is ordered as the list prices are.
  monthly: (a, b) => (pace ? monthly(a, pace) - monthly(b, pace) : ORDER.cheapest(a, b)),
  ...ORDER,
});

const ORDER: Record<Exclude<CatalogSort, 'monthly'>, (a: CatalogModel, b: CatalogModel) => number> = {
  cheapest: (a, b) => a.output_per_million - b.output_per_million || a.input_per_million - b.input_per_million,
  dearest: (a, b) => b.output_per_million - a.output_per_million || b.input_per_million - a.input_per_million,
  context: (a, b) => (b.context ?? 0) - (a.context ?? 0),
  measured: (a, b) => (wellFormed(b) ?? -1) - (wellFormed(a) ?? -1) || b.tool_calls - a.tool_calls,
  name: (a, b) => (a.name ?? a.model).localeCompare(b.name ?? b.model),
};

/** The catalog as filtered and sorted; the slug breaks every tie, so the order is stable. */
export function findIn(models: CatalogModel[], f: CatalogFilter, env: Envelope, pace: Pace = null): CatalogModel[] {
  const by = order(pace);
  const words = f.query.toLowerCase().split(/\s+/).filter(Boolean);
  return models
    .filter(
      (m) =>
        matches(m, words) &&
        (!f.provider || provider(m) === f.provider) &&
        (!f.tools || m.tools) &&
        (!f.envelope || inside(m, env)) &&
        (!f.measured || m.tool_calls > 0) &&
        (f.maxOutput === null || m.output_per_million <= f.maxOutput) &&
        (f.minContext === null || (m.context ?? 0) >= f.minContext),
    )
    .sort((a, b) => by[f.sort](a, b) || a.model.localeCompare(b.model));
}

/** How many filters narrow the list beyond the defaults, for "Clear". */
export function narrowed(f: CatalogFilter): boolean {
  return (Object.keys(NO_FILTER) as (keyof CatalogFilter)[]).some((k) => k !== 'sort' && f[k] !== NO_FILTER[k]);
}
