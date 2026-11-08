import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it } from 'vitest';
import * as stories from './CorrespondencePage.stories';

const { Everyone, NoneYet } = composeStories(stories);

const heads = () => screen.getAllByText(/^(From \w+|Lily’s) · with /).map((p) => p.textContent);

// Correspondence (the witness, 2026-11-08, Lily's letter #330): filter
// first, time order the spine, whose each is said.
describe('Correspondence', () => {
  afterEach(cleanup);

  it('lists every message in time order, each saying whose it is', () => {
    render(<Everyone />);
    expect(heads()).toEqual(['From Jack · with Jack', 'From Grace · with Grace', 'Lily’s · with Jack', 'From Jack · with Jack']);
    fireEvent.click(screen.getByRole('checkbox', { name: 'Newest first' }));
    expect(heads()[0]).toBe('From Jack · with Jack');
    expect(heads()[1]).toBe('Lily’s · with Jack');
  });

  it('filters by participant with no phrase, and by conversation', () => {
    render(<Everyone />);
    fireEvent.change(screen.getByRole('combobox', { name: 'Participant' }), { target: { value: 'Jack' } });
    expect(heads()).toEqual(['From Jack · with Jack', 'Lily’s · with Jack', 'From Jack · with Jack']);
    expect(screen.getByText('3 messages')).toBeTruthy();
    fireEvent.change(screen.getByRole('combobox', { name: 'Participant' }), { target: { value: '' } });
    const options = Array.from((screen.getByRole('combobox', { name: 'Conversation' }) as HTMLSelectElement).options).map((o) => o.text);
    expect(options).toEqual(['Every conversation', 'With Jack: Your piece (3)', 'With Grace: The directory (1)']);
    cleanup();
    render(<NoneYet />);
    expect(screen.getByText('None yet.')).toBeTruthy();
  });
});
