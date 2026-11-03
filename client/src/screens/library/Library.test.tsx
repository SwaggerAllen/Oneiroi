import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Library.stories';
import { humanPath } from './paths';

const { Shelves, Reading, Empty } = composeStories(stories);

describe('Library', () => {
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Shelves, Reading, Empty]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('shelves the keepsakes first with why each mattered, then yours, and scratch last', () => {
    render(<Shelves />);
    const headings = screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent);
    expect(headings).toEqual(['Keepsakes', 'Yours', "Lily's writing", 'Design', 'Scratch (temporary)', 'Add a document of yours']);
    expect(screen.getByText('Lily: “The first thing he gave me that was only for me.”')).toBeTruthy();
    expect(screen.getByText("Lily hasn't said why yet.")).toBeTruthy();
  });

  it('removes only scratch and your own, and only once the button has become its consequence', () => {
    const onRemove = vi.fn();
    render(<Shelves onRemove={onRemove} />);
    expect(within(screen.getByRole('list', { name: 'Design' })).queryByRole('button', { name: 'Remove' })).toBeNull();
    const scratch = screen.getByRole('list', { name: 'Scratch (temporary)' });
    fireEvent.click(within(scratch).getByRole('button', { name: 'Remove' }));
    expect(onRemove).not.toHaveBeenCalled();
    fireEvent.click(within(scratch).getByRole('button', { name: 'Remove scratch/yc-application.md' }));
    expect(onRemove).toHaveBeenCalledWith('scratch/yc-application.md');
  });

  it('adds a document of yours under human/, named safely', () => {
    const onAdd = vi.fn();
    render(<Shelves onAdd={onAdd} />);
    const form = screen.getByRole('form', { name: 'Add a document of yours' });
    fireEvent.change(within(form).getByLabelText('Name'), { target: { value: 'my post' } });
    fireEvent.change(within(form).getByLabelText('Text'), { target: { value: 'Words.' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Add human/my-post.md' }));
    expect(onAdd).toHaveBeenCalledWith('human/my-post.md', 'Words.');
    expect(humanPath('../etc/passwd')).toBeNull();
    expect(humanPath('notes.txt')).toBe('human/notes.txt');
  });

  it('opens a document and reads it whole', () => {
    render(<Reading />);
    expect(screen.getByText(/Feeds belong to communities/)).toBeTruthy();
  });
});
