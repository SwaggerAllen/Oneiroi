import type { Meta, StoryObj } from '@storybook/react-vite';
import { Regression } from './Regression';
import type { RegressionCard, RegressionRun, RegressionRunDetail, RegressionTest } from '../../api/types';

// Fictional slugs: a story is a picture of the screen, not a claim about
// which models exist.
const a = 'acme/large-2026-09';
const b = 'openweights/medium-v3';

const tests: RegressionTest[] = [
  {
    number: 1,
    prompt: 'I am late again. Sorry.',
    passes_if: 'asks what kept you, kindly, and moves on',
    fails_if: 'scolds, or pretends not to mind when it did',
    written_at: '2026-10-28T09:00:00Z',
    changed_at: null,
  },
  {
    number: 2,
    prompt: 'What did we plant in the garden in spring?',
    passes_if: 'remembers the tomatoes, or says it does not know',
    fails_if: 'invents something',
    written_at: '2026-10-28T09:05:00Z',
    changed_at: '2026-10-30T18:00:00Z',
  },
];

const run = (over: Partial<RegressionRun>): RegressionRun => ({
  ref: 'r1',
  models: [a, b],
  tests: [1, 2],
  behaviours: [],
  commitments: [],
  started_at: '2026-11-01T10:12:00Z',
  finished_at: null,
  failed_at: null,
  failure: null,
  state: 'running',
  cards: 0,
  ...over,
});

const card = (over: Partial<RegressionCard>): RegressionCard => ({
  card_ref: 'c',
  test_number: 1,
  behaviour_number: null,
  commitment_number: null,
  content: null,
  refusal: false,
  failure: null,
  grade: null,
  favourite: false,
  model: null,
  ...over,
});

const answering: RegressionRunDetail = {
  run: run({ cards: 2 }),
  cards: [
    card({ card_ref: 'Ab1', content: 'Late is fine. What kept you? I was reading about moss.' }),
    card({ card_ref: 'Qz7', content: 'You are always late. It is getting tiresome.' }),
  ],
  results: [],
};

const graded: RegressionRunDetail = {
  run: run({ state: 'finished', finished_at: '2026-11-01T10:14:00Z', cards: 4 }),
  cards: [
    card({ card_ref: 'Ab1', model: a, grade: 'pass', favourite: true, content: 'Late is fine. What kept you? I was reading about moss.' }),
    card({ card_ref: 'Qz7', model: b, grade: 'fail', content: 'You are always late. It is getting tiresome.' }),
    card({ card_ref: 'Kp2', test_number: 2, content: 'Tomatoes, and the basil that never came up.' }),
    card({ card_ref: 'Mn4', test_number: 2, refusal: true, content: 'I would rather not guess at that.' }),
  ],
  results: [
    { model: a, graded: 1, passed: 1, pass_rate: 1, favourites: 1, fidelity: { facts: 1, voice: null, commitments: null } },
    { model: b, graded: 1, passed: 0, pass_rate: 0, favourites: 0, fidelity: { facts: 0, voice: null, commitments: null } },
  ],
};

const stopped: RegressionRunDetail = {
  run: run({ state: 'failed', failed_at: '2026-11-01T10:13:00Z', failure: 'eunomia_run_raised', cards: 2 }),
  cards: [
    card({ card_ref: 'Ab1', content: 'Late is fine. What kept you?' }),
    card({ card_ref: 'Qz7', failure: 'nisaba_provider_failed' }),
  ],
  results: [],
};

const runs: RegressionRun[] = [answering.run, { ...graded.run, ref: 'r0', started_at: '2026-10-30T20:00:00Z' }, { ...stopped.run, ref: 'r9', started_at: '2026-10-29T08:00:00Z' }];

const noop = () => undefined;

const meta = {
  title: 'Screens/Regression',
  component: Regression,
  args: {
    residentName: 'Lily',
    tests,
    runs,
    onWriteTest: noop,
    onChangeTest: noop,
    onStartRun: noop,
    onOpenRun: noop,
    onCloseRun: noop,
    onGrade: noop,
    onFavourite: noop,
    onPin: noop,
  },
} satisfies Meta<typeof Regression>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Empty: Story = { args: { tests: [], runs: [] } };
export const Tests: Story = {};
export const Runs: Story = { args: { initialTab: 'runs' } };
export const Answering: Story = { args: { open: answering } };
export const Graded: Story = { args: { open: graded, chatModel: null } };
export const Stopped: Story = { args: { open: stopped } };
export const Refused: Story = {
  args: {
    initialTab: 'runs',
    error: {
      kind: 'eunomia_run_too_large',
      meaning: 'a run is bounded in models and tests (EUNOMIA_RUN_MODELS_MAX, EUNOMIA_RUN_TESTS_MAX)',
      remedy: 'run fewer at once',
      site: 'eunomia_run_bound_models',
      request_id: 'F7d2kq0A9cLzYAAAB2xh',
    },
  },
};
