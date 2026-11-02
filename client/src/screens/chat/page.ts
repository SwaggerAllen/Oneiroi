import type { Message } from '../../api/types';

// A message's place in its session, `sequence:position`, compared as the
// two numbers it is: "10:0" is after "9:3", which a string compare gets
// wrong.
export function compareCursor(a: string, b: string): number {
  const [as, ap] = a.split(':').map(Number);
  const [bs, bp] = b.split(':').map(Number);
  return as !== bs ? as - bs : ap - bp;
}

// The newest page read again (after a turn lands) joined to what was
// already paged in: everything older than the page's first message is
// kept, the page replaces the rest. A page without cursors, or one that
// reaches back past everything loaded, simply replaces it.
export function mergeNewest(loaded: Message[], page: Message[]): Message[] {
  const first = page[0]?.cursor;
  if (!first) return page;
  const older = loaded.filter((m) => m.cursor !== undefined && compareCursor(m.cursor, first) < 0);
  return [...older, ...page];
}

// Where the reader left off: the index of the first message after the
// last one they read that someone else wrote, or -1 when nothing is new
// (or nothing was ever read here, so there is no place to have left).
export function firstUnread(messages: Message[], lastRead: string | null): number {
  if (!lastRead) return -1;
  return messages.findIndex((m) => m.cursor !== undefined && m.role !== 'user' && compareCursor(m.cursor, lastRead) > 0);
}

// The newest cursor among the messages, for "read up to here".
export function newestCursor(messages: Message[]): string | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const cursor = messages[i].cursor;
    if (cursor) return cursor;
  }
  return null;
}

// What a collapsed tool call shows: its first line, and how long the
// whole is when there is more than the line.
export function toolSummary(content: string): { line: string; more: string | null } {
  const lines = content.split('\n');
  // The width cuts the line on screen; this keeps a line of thousands of
  // characters out of the summary's text altogether.
  const line = lines[0].length > 200 ? `${lines[0].slice(0, 200)}…` : lines[0];
  if (lines.length === 1 && lines[0].length <= 120) return { line, more: null };
  const chars = content.length.toLocaleString('en-US');
  return { line, more: lines.length > 1 ? `${lines.length} lines · ${chars} characters` : `${chars} characters` };
}
