import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api, type Invite, type Platform } from '../../api/client';
import type { FeedbackReport } from '../../api/types';
import { SubjectContext } from '../state/resident';
import { draftOf, skuOf, standing } from './logic';
import { Operator } from './Operator';

const platform: Platform = {
  gate: { state: 'invite', note: 'the alpha', set_by: null, set_at: null },
  roles: [
    {
      account_id: 'a1',
      email: 'op@example.com',
      role: 'super_admin',
      note: null,
      granted_by: null,
      granted_at: '2026-10-01T00:00:00Z',
    },
    {
      account_id: 'a2',
      email: 'help@example.com',
      role: 'admin',
      note: 'support',
      granted_by: 'a1',
      granted_at: '2026-10-02T00:00:00Z',
    },
  ],
  triage: {
    slug: 'mira',
    from: 'setting',
    note: null,
    set_by: 'a1',
    set_at: null,
  },
  restarts: [],
};

const defaults = {
  plan: 'alpha',
  price_nanos: 20_000_000_000,
  discount_pct: 100,
  term_days: 90,
  uses: 1,
  expires_at: null,
};
const invite: Invite = {
  id: 'i1',
  plan: 'alpha',
  list_price_nanos: 20_000_000_000,
  discount_pct: 100,
  price_nanos: 0,
  term_days: 90,
  uses: 1,
  redeemed: 0,
  expires_at: null,
  note: 'for Sam',
  issued_at: '2026-11-01T00:00:00Z',
  revoked_at: null,
  revoke_note: null,
};
const report: FeedbackReport = {
  number: 7,
  kind: 'bug',
  surface: 'chat',
  body: 'It froze.',
  trace_id: 't-1',
  author_kind: 'witness',
  status: 'new',
  note: null,
  filed_at: '2026-11-09T00:00:00Z',
};

function mount() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  render(
    <QueryClientProvider client={client}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
        <Operator />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

const tab = (name: string) => fireEvent.click(screen.getByRole('radio', { name }));

describe('next Operator', () => {
  beforeEach(() => {
    vi.spyOn(api, 'platform').mockResolvedValue(platform);
    vi.spyOn(api, 'opsFailures').mockResolvedValue({
      failures: [],
      discarded_jobs: [],
    } as unknown as Awaited<ReturnType<typeof api.opsFailures>>);
    vi.spyOn(api, 'heartbeats').mockResolvedValue([]);
    vi.spyOn(api, 'invites').mockResolvedValue({ invites: [invite], defaults });
    vi.spyOn(api, 'allFeedback').mockResolvedValue([report]);
  });
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('issues a code from the defaults with a note, and shows it once with Copy', async () => {
    const issue = vi.spyOn(api, 'issueInvite').mockResolvedValue({ id: 'i2', code: 'ABCD-EFGH' });
    mount();
    tab('Invites');
    const form = await screen.findByRole('region', { name: 'Issue a code' });
    const submit = within(form).getByRole('button', {
      name: 'Issue a code',
    }) as HTMLButtonElement;
    expect(submit.disabled).toBe(true);
    fireEvent.change(within(form).getByLabelText("Who it's for, or why (required)"), { target: { value: 'for Ana' } });
    fireEvent.change(within(form).getByLabelText('Uses'), {
      target: { value: '3' },
    });
    fireEvent.click(submit);
    await waitFor(() =>
      expect(issue).toHaveBeenCalledWith({
        note: 'for Ana',
        plan: 'alpha',
        price_cents: 2000,
        discount_pct: 100,
        term_days: 90,
        uses: 3,
      }),
    );
    const shown = await screen.findByRole('region', { name: 'The new code' });
    expect(within(shown).getByText('ABCD-EFGH')).toBeTruthy();
    expect(within(shown).getByRole('button', { name: 'Copy' })).toBeTruthy();
  });

  it('revokes a code only with a note', async () => {
    const revoke = vi.spyOn(api, 'revokeInvite').mockResolvedValue(undefined);
    mount();
    tab('Invites');
    const codes = await screen.findByRole('region', { name: 'Codes issued' });
    fireEvent.click(await within(codes).findByRole('button', { name: 'Revoke' }));
    const confirm = within(codes).getByRole('button', {
      name: 'Revoke the code “for Sam”',
    }) as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
    fireEvent.change(within(codes).getByRole('textbox', { name: /Why revoke/ }), { target: { value: 'not needed' } });
    fireEvent.click(confirm);
    await waitFor(() => expect(revoke).toHaveBeenCalledWith('i1', 'not needed'));
  });

  it('grants a role by email with a note, and revokes one with its own', async () => {
    const grant = vi.spyOn(api, 'grantRole').mockResolvedValue(undefined);
    const revoke = vi.spyOn(api, 'revokeRole').mockResolvedValue(undefined);
    mount();
    tab('Roles');
    const form = await screen.findByRole('region', { name: 'Grant a role' });
    fireEvent.change(within(form).getByLabelText('Account email'), {
      target: { value: 'next@example.com' },
    });
    fireEvent.change(within(form).getByLabelText('Role'), {
      target: { value: 'super_admin' },
    });
    fireEvent.change(within(form).getByLabelText('Why (recorded with the grant)'), { target: { value: 'hand-off' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Grant' }));
    await waitFor(() => expect(grant).toHaveBeenCalledWith('next@example.com', 'super_admin', 'hand-off'));
    expect(await screen.findByText('Granted Super admin to next@example.com.')).toBeTruthy();

    const roles = screen.getByRole('region', { name: 'Platform roles' });
    fireEvent.click(within(roles).getAllByRole('button', { name: 'Revoke' })[1]);
    fireEvent.change(within(roles).getByRole('textbox', { name: /Why revoke/ }), { target: { value: 'left' } });
    fireEvent.click(
      within(roles).getByRole('button', {
        name: 'Revoke Admin from help@example.com',
      }),
    );
    await waitFor(() => expect(revoke).toHaveBeenCalledWith('a2', 'admin', 'left'));
  });

  it("says the server's refusal and keeps what was typed", async () => {
    vi.spyOn(api, 'grantRole').mockRejectedValue(new Error('No such account.'));
    mount();
    tab('Roles');
    const form = await screen.findByRole('region', { name: 'Grant a role' });
    fireEvent.change(within(form).getByLabelText('Account email'), {
      target: { value: 'nobody@example.com' },
    });
    fireEvent.change(within(form).getByLabelText('Why (recorded with the grant)'), { target: { value: 'try' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Grant' }));
    expect(await screen.findByText('No such account.')).toBeTruthy();
    expect((within(form).getByLabelText('Account email') as HTMLInputElement).value).toBe('nobody@example.com');
  });

  it('sets the triage desk, or nobody, with a note', async () => {
    const set = vi.spyOn(api, 'setTriage').mockResolvedValue({
      slug: null,
      from: 'setting',
      note: 'x',
      set_by: 'a1',
      set_at: null,
    });
    mount();
    tab('Triage');
    const desk = await screen.findByRole('region', { name: 'Triage desk' });
    expect(await within(desk).findByText('mira')).toBeTruthy();
    fireEvent.change(within(desk).getByLabelText('Why (recorded with the change)'), { target: { value: 'away' } });
    fireEvent.click(within(desk).getByRole('button', { name: 'Nobody' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith(null, 'away'));
  });

  it('opens a report with what the platform logged, and moves it with a note the reporter reads', async () => {
    vi.spyOn(api, 'feedbackReport').mockResolvedValue({
      ...report,
      failures: [
        {
          at: '2026-11-09T00:00:01Z',
          level: 'error',
          component: 'chat',
          error_kind: 'timeout',
          error_site: 'stream',
          message: 'gave up',
        },
      ],
    });
    const move = vi.spyOn(api, 'moveFeedback').mockResolvedValue(undefined);
    mount();
    tab('Triage');
    fireEvent.click(await screen.findByRole('button', { name: /#7 problem/ }));
    const open = await screen.findByLabelText('Report 7');
    expect(within(open).getByRole('list', { name: 'What the platform logged' }).textContent).toContain('gave up');
    const mark = within(open).getByRole('button', {
      name: 'Mark in work',
    }) as HTMLButtonElement;
    expect(mark.disabled).toBe(true);
    expect(within(open).queryByRole('button', { name: 'Mark new' })).toBeNull();
    fireEvent.change(within(open).getByLabelText('A note the reporter reads (required)'), { target: { value: 'looking' } });
    fireEvent.click(mark);
    await waitFor(() => expect(move).toHaveBeenCalledWith(7, 'in_work', 'looking'));
  });
});

describe('operator logic', () => {
  it('builds the request from a draft, and refuses one without a note or with a bad number', () => {
    const d = draftOf(defaults);
    expect(skuOf(d)).toBeNull();
    expect(skuOf({ ...d, note: 'x', expires: '2026-12-01' })).toMatchObject({
      note: 'x',
      price_cents: 2000,
      expires_at: new Date('2026-12-01').toISOString(),
    });
    expect(skuOf({ ...d, note: 'x', uses: 'two' })).toBeNull();
    expect(skuOf({ ...d, note: 'x', uses: '' })).toBeNull();
  });

  it('says where a code stands', () => {
    const now = new Date('2026-11-10T00:00:00Z');
    expect(standing(invite, now)).toBe('0 of 1 used');
    expect(standing({ ...invite, redeemed: 1 }, now)).toBe('spent');
    expect(standing({ ...invite, expires_at: '2026-11-01T00:00:00Z' }, now)).toBe('expired');
    expect(standing({ ...invite, revoked_at: '2026-11-02T00:00:00Z' }, now)).toBe('revoked');
  });
});
