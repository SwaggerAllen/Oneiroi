import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Kinds.stories';

const { Shelf, NoProposals } = composeStories(stories);

describe('Kinds', () => {
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Shelf, NoProposals]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  // seshat#51: every kind with its gate, hers marked; a system kind's gate
  // goes on at a click, off only as a proposal she answers.
  it('lists each kind with its gate, and moves a gate on at once or proposes it off with a note', () => {
    const onGate = vi.fn();
    render(<Shelf onGate={onGate} />);
    const items = within(screen.getByRole('list', { name: 'Kinds' })).getAllByRole('listitem');
    expect(items.map((li) => li.querySelector(':scope > span:nth-child(2)')?.textContent)).toEqual([
      'writing/ · waits on you at review',
      'design/ · no gate',
      'notes/ · no gate',
      "field-notes/ · waits on you at review · Lily's, defined by Lily",
    ]);
    // Writing has an open proposal: no second one is offered.
    expect(within(items[0]).getByText('A gate proposal is open.')).toBeTruthy();
    // Notes is not a gated kind; field-notes is hers and moves by its descriptor.
    expect(within(items[2]).queryByRole('button')).toBeNull();
    expect(within(items[3]).queryByRole('button')).toBeNull();
    fireEvent.click(within(items[1]).getByRole('button', { name: 'Gate on' }));
    expect(onGate).toHaveBeenCalledWith('design', true, '');
    cleanup();
    render(<NoProposals onGate={onGate} />);
    const off = screen.getByRole('button', { name: 'Propose gate off' }) as HTMLButtonElement;
    expect(off.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('A note for the next change'), { target: { value: 'trust the drafts' } });
    fireEvent.click(off);
    expect(onGate).toHaveBeenLastCalledWith('writing', false, 'trust the drafts');
  });

  it("answers her gate proposal with a note, and shows his own as waiting for her", () => {
    const onAnswer = vi.fn();
    render(<Shelf onAnswer={onAnswer} />);
    const open = screen.getByRole('region', { name: 'Open gate proposals' });
    expect(open.textContent).toMatch(/#2 the writing gate off, proposed by Lily: drafts can go straight out/);
    fireEvent.change(screen.getByLabelText('A note for the next change'), { target: { value: 'yes' } });
    fireEvent.click(within(open).getByRole('button', { name: 'Decline' }));
    expect(onAnswer).toHaveBeenCalledWith(2, false, 'yes');
    expect(screen.getByRole('region', { name: 'Lately answered' }).textContent).toMatch(/#1 the design gate on: agreed/);
  });

  it('defines a kind of hers by a name that is its folder, never a system kind', () => {
    const onDefine = vi.fn();
    render(<Shelf onDefine={onDefine} />);
    const form = within(screen.getByRole('form', { name: 'Define a kind' }));
    const define = form.getByRole('button', { name: 'Define the kind' }) as HTMLButtonElement;
    fireEvent.change(form.getByLabelText('Name'), { target: { value: 'notes' } });
    expect(define.disabled).toBe(true);
    fireEvent.change(form.getByLabelText('Name'), { target: { value: 'Dreams!' } });
    expect(define.disabled).toBe(true);
    fireEvent.change(form.getByLabelText('Name'), { target: { value: 'dreams' } });
    fireEvent.change(form.getByLabelText('Label'), { target: { value: 'Dreams' } });
    fireEvent.click(form.getByRole('checkbox', { name: /waits on you/ }));
    fireEvent.change(form.getByLabelText('What you are asked'), { target: { value: 'Read the dream' } });
    fireEvent.click(define);
    expect(onDefine).toHaveBeenCalledWith({ kind: 'dreams', label: 'Dreams', cites: false, approvable: true, ask: 'Read the dream', note: undefined });
  });
});
