import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Plugins.stories';

const { WithAProposal } = composeStories(stories);

// brain#68: plugins are contract material; every change carries a note.
describe('Plugins', () => {
  afterEach(cleanup);

  it('lists each slot with its state and its carry-over, and changes nothing without a note', () => {
    const onPropose = vi.fn();
    render(<WithAProposal onPropose={onPropose} />);
    const items = within(screen.getByRole('list', { name: 'Plugins' })).getAllByRole('listitem');
    expect(items[0].textContent).toContain('Your timeline (timeline) · on · carried over from before plugins');
    expect(items[2].textContent).toContain('installed, off');
    const off = within(items[0]).getByRole('button', { name: 'Propose off' }) as HTMLButtonElement;
    expect(off.disabled).toBe(true);
    fireEvent.change(screen.getByRole('textbox', { name: /note/ }), { target: { value: 'a test' } });
    fireEvent.click(off);
    expect(onPropose).toHaveBeenCalledWith('timeline', 'off', 'a test');
    // A slot with an open proposal offers nothing more until it is answered.
    expect(within(items[1]).queryByRole('button')).toBeNull();
    fireEvent.click(within(items[2]).getByRole('button', { name: 'Propose on' }));
    expect(onPropose).toHaveBeenCalledWith('honcho', 'on', 'a test');
  });

  it("answers her proposal with the note, and shows what was answered lately", () => {
    const onAnswer = vi.fn();
    render(<WithAProposal onAnswer={onAnswer} />);
    fireEvent.change(screen.getByRole('textbox', { name: /note/ }), { target: { value: 'yes, for the week' } });
    fireEvent.click(within(screen.getByRole('region', { name: 'Open proposals' })).getByRole('button', { name: 'Agree' }));
    expect(onAnswer).toHaveBeenCalledWith(2, true, 'yes, for the week');
    expect(screen.getByRole('region', { name: 'Lately answered' }).textContent).toContain('#1 off honcho: agreed, "fine"');
  });

  it("shows an installed plugin's audit, and switches it off at one word", () => {
    const onOff = vi.fn();
    render(<WithAProposal onOff={onOff} />);
    const heron = within(screen.getByRole('list', { name: 'Plugins' })).getAllByRole('listitem')[3];
    expect(heron.textContent).toContain('by the house');
    expect(heron.textContent).toContain('Its files no longer match what was installed.');
    expect(heron.textContent).toContain('The catalog holds a newer version');
    expect(heron.textContent).toContain("In Lily's context on 3 turns.");
    fireEvent.change(screen.getByRole('textbox', { name: /note/ }), { target: { value: 'enough' } });
    fireEvent.click(within(heron).getByRole('button', { name: 'Switch off' }));
    expect(onOff).toHaveBeenCalledWith('heron-notes', 'enough');
  });
});
