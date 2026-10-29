// The shapes the JSON surface answers with (spec §2), written by hand
// against the routes of OneiroiWeb. The OpenAPI document the server
// serves at /v1/openapi.json types its bodies as bare objects and arrays
// today, so a generated client would type everything `unknown`; these
// are the claim a generated client replaces once the document carries
// schemas (spec §6.15, open for the author).

export type ActorKind = 'steward' | 'resident' | 'judge' | 'hands' | 'job' | 'platform';

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

export interface ApiError {
  kind: string;
  meaning: string;
  remedy?: string;
}
