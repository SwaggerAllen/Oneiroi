import type { HouseLetter } from '../../api/types';

// Where a house letter stands, read off the letters themselves
// (design/correspondence-pipeline.md, "The queue"): answered when another
// letter replies to it; closed when it is itself a reply and has been
// read, since a reply asks for nothing back; in hand when read and not
// yet answered; waiting
// on the clock when it is a brief to Free time nobody has read; waiting on
// whoever it is addressed to otherwise. Nothing is written to say so.
export type LetterState =
  | { kind: 'answered'; by: number }
  | { kind: 'closed'; readBy: string[] }
  | { kind: 'in_hand'; readBy: string[] }
  | { kind: 'waiting'; on: string; clock: boolean };

export function letterState(letter: HouseLetter, all: HouseLetter[]): LetterState {
  const reply = all.find((l) => l.in_reply_to === letter.number);
  if (reply) return { kind: 'answered', by: reply.number };
  if (letter.read_by.length > 0 && letter.in_reply_to !== null) return { kind: 'closed', readBy: letter.read_by };
  if (letter.read_by.length > 0) return { kind: 'in_hand', readBy: letter.read_by };
  if (letter.to === 'Free time') return { kind: 'waiting', on: 'the next free time', clock: true };
  if (letter.to === 'house') return { kind: 'waiting', on: 'any of Lily’s conversations', clock: false };
  return { kind: 'waiting', on: letter.to, clock: false };
}

// Whether a letter still asks something of someone.
export function isOpen(state: LetterState): boolean {
  return state.kind === 'in_hand' || state.kind === 'waiting';
}

export function stateLine(state: LetterState): string {
  switch (state.kind) {
    case 'answered':
      return `answered in #${state.by}`;
    case 'closed':
      return `read by ${state.readBy.join(', ')}`;
    case 'in_hand':
      return `read by ${state.readBy.join(', ')}, not answered yet`;
    case 'waiting':
      return state.clock ? `waiting for ${state.on}` : `unread, waiting for ${state.on}`;
  }
}
