import { beforeEach, describe, expect, it } from 'vitest';
import { formatHash, parseHash } from './routes';
import { topOf, useShell } from './store';

describe('routes', () => {
  it('parses and formats a tab with a path', () => {
    const loc = parseHash('#/records/doc/etymologies/oneiric.md');
    expect(loc).toEqual({ tab: 'records', path: 'doc/etymologies/oneiric.md' });
    expect(formatHash(loc)).toBe('#/records/doc/etymologies/oneiric.md');
  });

  it('falls back to chat for an unknown or empty hash', () => {
    expect(parseHash('')).toEqual({ tab: 'chat', path: '' });
    expect(parseHash('#/nowhere/x')).toEqual({ tab: 'chat', path: '' });
  });
});

describe('stacks', () => {
  beforeEach(() => useShell.setState(useShell.getInitialState()));

  it('keeps each tab where it was across switches', () => {
    const s = useShell.getState();
    s.setTab('records');
    s.push('doc/a');
    s.push('doc/b');
    s.setTab('chat');
    s.setTab('records');
    expect(topOf(useShell.getState().stacks, 'records')).toBe('doc/b');
  });

  it('pops back within a tab, never past its root', () => {
    const s = useShell.getState();
    s.setTab('time');
    s.push('day/2026-11-09');
    s.back();
    s.back();
    expect(useShell.getState().stacks.time).toEqual(['']);
  });

  it('cuts the stack back when the URL goes back to a path on it', () => {
    const s = useShell.getState();
    s.go({ tab: 'records', path: 'doc/a' });
    s.go({ tab: 'records', path: 'doc/b' });
    s.go({ tab: 'records', path: 'doc/a' });
    expect(useShell.getState().stacks.records).toEqual(['', 'doc/a']);
  });

  it('notes when the connection was first lost', () => {
    const s = useShell.getState();
    s.setConnection('offline', 1000);
    s.setConnection('connecting', 5000);
    expect(useShell.getState().offlineSince).toBe(1000);
    s.setConnection('connected', 9000);
    expect(useShell.getState().offlineSince).toBeNull();
  });
});
