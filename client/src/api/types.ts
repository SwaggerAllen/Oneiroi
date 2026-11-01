// The shapes the JSON surface answers with (spec §2), written by hand
// against the routes of OneiroiWeb. The OpenAPI document the server
// serves at /v1/openapi.json types its bodies as bare objects and arrays
// today, so a generated client would type everything `unknown`; these
// are the claim a generated client replaces once the document carries
// schemas (spec §6.15, open for the author).

export type ActorKind = 'witness' | 'resident' | 'judge' | 'hands' | 'job' | 'platform';

export interface Actor {
  kind: ActorKind | string;
  id: string | null;
  model: string | null;
}

export interface Resident {
  id: string;
  slug: string;
  name: string;
  state: string;
  first_contact_at: string | null;
  formation_until: string | null;
  chat_model: string | null;
}

export interface Session {
  key: string;
  resident_id: string;
  kind: string;
  adapter: string | null;
  turns: number;
  last_turn_at: string | null;
  summary: string | null;
}

export interface Message {
  session_key: string;
  turn_ref: string;
  role: 'user' | 'assistant' | 'system' | 'tool' | string;
  content: string;
  sent_at: string;
  actor: Actor;
  refusal: boolean;
}

export interface Injection {
  label: string;
  tokens: number;
  reason: string;
  position: number;
  text: string | null;
}

export interface Turn {
  turn_ref: string;
  messages: Array<{ role: string; content: string; sent_at: string; actor: Actor; refusal: boolean }>;
  drew_on: number;
  stopped?: { kind: string; meaning: string; remedy: string };
}

export interface Bookmark {
  number: number;
  line: string;
  summary: string | null;
  session_key: string;
  anchor_ref: string;
  anchor_at: string;
  turns_back: number;
  tags: string[];
  added_by: Actor;
  proposed_by: { kind: string; id: string } | null;
  pinned_by: { kind: string; id: string } | null;
  pinned_at: string | null;
  last_indexed_at: string | null;
}

export interface Tag {
  slug: string;
  state: 'proposed' | 'active' | 'retired' | 'rejected' | string;
  note: string | null;
}

export interface KeyStatus {
  present: boolean;
  stored_at: string | null;
}

export interface BudgetLine {
  purpose: string;
  period: 'day' | 'week' | 'month' | string;
  cap: string | null;
  spent: string;
  exceeded: boolean;
}

export interface SpendRow {
  key: string;
  calls: number;
  cost: string;
}

export interface Ledger {
  key: KeyStatus;
  purposes: string[];
  budgets: BudgetLine[];
  spend: {
    since: string;
    by_purpose: SpendRow[];
    by_model: SpendRow[];
    by_actor: SpendRow[];
  };
}

// The error envelope: what went wrong in words (`meaning`), what to do
// (`remedy`), and the reference that leads to the line that said so
// (`site`) and to the request's log lines (`request_id`), conventions §8.
export interface ApiError {
  kind: string;
  meaning: string;
  remedy?: string;
  site?: string;
  request_id?: string;
}

// Regression (spec §6.4, F42): tests are three texts; a run is models x
// trials answered in the background (eunomia #30); a card is blind, its
// model null until every card of its trial is graded.
export interface RegressionTest {
  number: number;
  prompt: string;
  passes_if: string;
  fails_if: string;
  written_at: string;
  changed_at: string | null;
}

export type TestTexts = Pick<RegressionTest, 'prompt' | 'passes_if' | 'fails_if'>;

export type RunState = 'running' | 'finished' | 'failed';

export interface RegressionRun {
  ref: string;
  models: string[];
  tests: number[];
  behaviours: number[];
  commitments: number[];
  started_at: string;
  finished_at: string | null;
  failed_at: string | null;
  failure: string | null;
  state: RunState;
  cards: number;
}

export type Grade = 'pass' | 'fail';

export interface RegressionCard {
  card_ref: string;
  test_number: number | null;
  behaviour_number: number | null;
  commitment_number: number | null;
  content: string | null;
  refusal: boolean;
  failure: string | null;
  grade: Grade | null;
  favourite: boolean;
  model: string | null;
}

export interface RegressionResult {
  model: string;
  graded: number;
  passed: number;
  pass_rate: number;
  favourites: number;
  fidelity: { facts: number | null; voice: number | null; commitments: number | null };
}

export interface RegressionRunDetail {
  run: RegressionRun;
  cards: RegressionCard[];
  results: RegressionResult[];
}

// What the run's channel pushes when the run ends.
export interface RunEnd {
  state: Exclude<RunState, 'running'>;
  cards: number;
}
