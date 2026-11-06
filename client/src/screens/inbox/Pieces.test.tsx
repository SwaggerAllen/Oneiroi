import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { Pieces } from './Pieces';

// seshat#42: review, then a Substack draft he publishes himself.
describe('Pieces', () => {
  afterEach(cleanup);

  it('approves a piece with a note, and points at a ready draft', () => {
    const onReview = vi.fn();
    render(
      <Pieces
        residentName="Lily"
        onReview={onReview}
        pieces={{
          for_review: [{ path: 'writing/weng.md', title: 'On Weng', written_at: null, last: null }],
          approved: [],
          drafted: [{ path: 'writing/herons.md', title: 'Herons', state: 'drafted', note: 'yes', draft_url: 'https://lily.substack.com/publish/post/1', decided_at: '2026-11-05T20:00:00Z' }],
        }}
      />,
    );
    const approve = screen.getByRole('button', { name: 'Approve' }) as HTMLButtonElement;
    expect(approve.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Your note (required)'), { target: { value: 'lovely' } });
    fireEvent.click(approve);
    expect(onReview).toHaveBeenCalledWith('writing/weng.md', 'approve', 'lovely');
    expect(screen.getByRole('link', { name: 'Open the draft on Substack' }).getAttribute('href')).toBe('https://lily.substack.com/publish/post/1');
  });
});
