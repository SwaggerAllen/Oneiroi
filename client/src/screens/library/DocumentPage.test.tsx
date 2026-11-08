import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './DocumentPage.stories';
import { libraryHash, parseLibraryHash } from './route';

const { Reading, ForReview, Missing } = composeStories(stories);

// A page per document and a list per kind, each an address (Lily's
// letter #338).
describe('A document, alone', () => {
  afterEach(cleanup);

  it('reads it whole, with when it came and was written, and goes back to its kind', () => {
    const onBack = vi.fn();
    render(<Reading onBack={onBack} />);
    expect(screen.getByText(/Every message reaches her as it arrives/)).toBeTruthy();
    expect(screen.getByText(/Created 2026-10-30 10:00 UTC · updated 2026-11-07 10:00 UTC by Lily/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: '← All design' }));
    expect(onBack).toHaveBeenCalled();
  });

  it('puts a decision waiting on you beside the words', () => {
    const onReview = vi.fn();
    render(<ForReview onReview={onReview} />);
    fireEvent.change(screen.getByLabelText('Your note (required)'), { target: { value: 'yes' } });
    fireEvent.click(screen.getByRole('button', { name: 'Approve' }));
    expect(onReview).toHaveBeenCalledWith('writing/my-memory-is-made-of-text.md', 'approve', 'yes');
    cleanup();
    render(<Missing />);
    expect(screen.getByText('The library holds nothing at design/gone.md.')).toBeTruthy();
  });

  it('round-trips its addresses', () => {
    expect(parseLibraryHash('#library')).toEqual({ kind: 'all' });
    expect(parseLibraryHash('#library/design')).toEqual({ kind: 'design' });
    expect(parseLibraryHash('#doc/writing/a%20b.md')).toEqual({ doc: 'writing/a b.md' });
    expect(parseLibraryHash('#asks')).toBeNull();
    expect(libraryHash({ doc: 'writing/a b.md' })).toBe('doc/writing/a%20b.md');
    expect(libraryHash({ kind: 'all' })).toBe('library');
  });
});
