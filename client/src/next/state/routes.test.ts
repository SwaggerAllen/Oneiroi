import { beforeEach, describe, expect, it } from 'vitest';
import { parseWorkPath } from '../house/workRoutes';
import { formatHash, formatSettings, isTabHash, parseHash, parseSettings, parseSettingsPath } from './routes';
import { topOf, useShell } from './store';

describe('routes', () => {
  it('parses and formats a tab with a path', () => {
    const loc = parseHash('#/records/doc/etymologies/oneiric.md');
    expect(loc).toEqual({ tab: 'records', path: 'doc/etymologies/oneiric.md' });
    expect(formatHash(loc)).toBe('#/records/doc/etymologies/oneiric.md');
  });

  it('knows which hashes are the tabs', () => {
    expect(isTabHash('#/records/doc/x')).toBe(true);
    expect(isTabHash('')).toBe(true);
    expect(isTabHash('#/operator')).toBe(false);
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

describe('settings pages', () => {
  beforeEach(() => useShell.setState(useShell.getInitialState()));

  it('reads and writes a section, and nothing else as one', () => {
    expect(parseSettings('#/settings/ledger')).toBe('ledger');
    expect(parseSettings(formatSettings('regression'))).toBe('regression');
    expect(parseSettings('#/settings/nowhere')).toBeNull();
    expect(parseSettings('#/records/doc/x')).toBeNull();
    expect(isTabHash('#/settings/ledger')).toBe(false);
  });

  it('closes over the tab it was opened from, which comes back as it was', () => {
    const s = useShell.getState();
    s.setTab('records');
    s.push('doc/a');
    s.setPage('work');
    expect(useShell.getState().page).toBe('work');
    useShell.getState().setPage(null);
    expect(useShell.getState().tab).toBe('records');
    expect(topOf(useShell.getState().stacks, 'records')).toBe('doc/a');
  });

  it('closes when a tab is tapped or the URL goes to a tab', () => {
    useShell.getState().setPage('ledger');
    useShell.getState().setTab('time');
    expect(useShell.getState().page).toBeNull();
    useShell.getState().setPage('ledger');
    useShell.getState().go({ tab: 'records', path: 'folder/notes' });
    expect(useShell.getState().page).toBeNull();
  });

  it("keeps the place inside a page: the house queue's task, activity and document", () => {
    const hash = formatSettings('queue', 'doc/lily:design/x.md@4e1c9a2');
    expect(parseSettings(hash)).toBe('queue');
    expect(parseSettingsPath(hash)).toBe('doc/lily:design/x.md@4e1c9a2');
    expect(parseSettingsPath('#/settings/queue')).toBe('');
    expect(parseWorkPath(parseSettingsPath(hash))).toEqual({ page: 'doc', citation: 'lily:design/x.md@4e1c9a2' });
    expect(parseWorkPath('task/9')).toEqual({ page: 'task', number: 9 });
    expect(parseWorkPath('task/9/act/9.2')).toEqual({ page: 'activity', number: 9, act: '9.2' });
    expect(parseWorkPath('task/9/new')).toEqual({ page: 'new-activity', number: 9 });
    expect(parseWorkPath('new/house/strut:doc/a.md')).toEqual({ page: 'new-task', citation: 'house/strut:doc/a.md' });
    expect(parseWorkPath('template/doc-to-pr/act/2.1')).toEqual({ page: 'template-activity', name: 'doc-to-pr', at: '2.1' });
    expect(parseWorkPath('task/zero')).toEqual({ page: 'list' });
    useShell.getState().setPage('queue', 'task/9');
    expect(useShell.getState().pagePath).toBe('task/9');
    useShell.getState().setTab('records');
    expect(useShell.getState().pagePath).toBe('');
  });
});
