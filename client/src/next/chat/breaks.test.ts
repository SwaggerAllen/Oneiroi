import { describe, expect, it } from 'vitest';
import { hardBreaks } from './breaks';

describe('hardBreaks', () => {
  it('keeps each line of a conversation, and leaves paragraphs and code alone', () => {
    expect(hardBreaks('Grace: hi\nAndrew: hello\n\nNext')).toBe('Grace: hi  \nAndrew: hello\n\nNext');
    expect(hardBreaks('```\na\nb\n```\nafter\nmore')).toBe('```\na\nb\n```\nafter  \nmore');
  });
});
