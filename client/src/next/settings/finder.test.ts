import { describe, expect, it } from 'vitest';
import type { CatalogModel } from '../../api/types';
import { findIn, monthly, narrowed, NO_FILTER, providers } from './finder';

const m = (model: string, input: number, output: number, extra: Partial<CatalogModel> = {}): CatalogModel => ({
  model,
  name: null,
  description: null,
  input_per_million: input,
  output_per_million: output,
  context: 128_000,
  tools: true,
  tool_calls: 0,
  tool_calls_failed: 0,
  fetched_at: null,
  ...extra,
});

const all = [
  m('openai/gpt-x', 2, 8, { name: 'GPT X', description: 'A fast reasoning model' }),
  m('anthropic/claude-y', 3, 15, { context: 200_000, tool_calls: 10, tool_calls_failed: 1 }),
  m('meta/llama-z', 0.1, 0.2, { tools: false }),
  m('openai/gpt-mini', 0.5, 2, { context: 32_000, tool_calls: 10, tool_calls_failed: 0 }),
];

const slugs = (ms: CatalogModel[]) => ms.map((x) => x.model);

describe('the catalog filter', () => {
  it('by default shows the tool-capable models, cheapest output first', () => {
    expect(slugs(findIn(all, NO_FILTER, null))).toEqual(['openai/gpt-mini', 'openai/gpt-x', 'anthropic/claude-y']);
  });

  it('matches every word anywhere in slug, name or blurb, in any case', () => {
    expect(slugs(findIn(all, { ...NO_FILTER, query: 'FAST gpt' }, null))).toEqual(['openai/gpt-x']);
    expect(slugs(findIn(all, { ...NO_FILTER, query: 'llama', tools: false }, null))).toEqual(['meta/llama-z']);
  });

  it('narrows by provider, price cap, context floor and measurement', () => {
    expect(slugs(findIn(all, { ...NO_FILTER, provider: 'openai' }, null))).toEqual(['openai/gpt-mini', 'openai/gpt-x']);
    expect(slugs(findIn(all, { ...NO_FILTER, maxOutput: 8 }, null))).toEqual(['openai/gpt-mini', 'openai/gpt-x']);
    expect(slugs(findIn(all, { ...NO_FILTER, minContext: 200_000 }, null))).toEqual(['anthropic/claude-y']);
    expect(slugs(findIn(all, { ...NO_FILTER, measured: true }, null))).toEqual(['openai/gpt-mini', 'anthropic/claude-y']);
  });

  it('keeps to the envelope only when asked and when there is one', () => {
    const env = { input_per_million: 2, output_per_million: 8 };
    expect(slugs(findIn(all, { ...NO_FILTER, envelope: true }, env))).toEqual(['openai/gpt-mini', 'openai/gpt-x']);
    expect(findIn(all, { ...NO_FILTER, envelope: true }, null)).toHaveLength(3);
  });

  it('sorts by context, measured share and name', () => {
    expect(slugs(findIn(all, { ...NO_FILTER, sort: 'context' }, null))[0]).toBe('anthropic/claude-y');
    expect(slugs(findIn(all, { ...NO_FILTER, sort: 'measured' }, null))).toEqual(['openai/gpt-mini', 'anthropic/claude-y', 'openai/gpt-x']);
    expect(slugs(findIn(all, { ...NO_FILTER, sort: 'dearest' }, null))[0]).toBe('anthropic/claude-y');
  });

  it('prices a month of her pace, and sorts by it', () => {
    const pace = { input_per_day: 1_000_000, output_per_day: 100_000 };
    // (1 M × $2 + 0.1 M × $8) a day × 30 = $84.
    expect(monthly(all[0], pace)).toBeCloseTo(84);
    expect(slugs(findIn(all, { ...NO_FILTER, sort: 'monthly' }, null, pace))).toEqual(['openai/gpt-mini', 'openai/gpt-x', 'anthropic/claude-y']);
    // Input-heavy, the order follows the input price.
    const reading = { input_per_day: 10_000_000, output_per_day: 0 };
    expect(slugs(findIn(all, { ...NO_FILTER, sort: 'monthly' }, null, reading))[2]).toBe('anthropic/claude-y');
  });

  it('counts providers, most models first', () => {
    expect(providers(all)[0]).toEqual({ name: 'openai', count: 2 });
  });

  it('knows when anything but the sort narrows', () => {
    expect(narrowed({ ...NO_FILTER, sort: 'name' })).toBe(false);
    expect(narrowed({ ...NO_FILTER, query: 'x' })).toBe(true);
  });
});
