import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Library.stories';
import { humanPath } from './paths';

const { Shelves, Reading, Empty, Searched } = composeStories(stories);

describe('Library', () => {
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Shelves, Reading, Empty, Searched]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('puts a tab per kind across the top, All first, keepsakes and yours before the work and scratch last', () => {
    render(<Shelves />);
    const tabs = screen.getAllByRole('tab').map((t) => t.textContent);
    expect(tabs.map((t) => t?.replace(/\d+$/, '').trim())).toEqual(['All', 'Keepsakes', 'Yours', 'Writing', 'Design', 'Scratch']);
    expect(screen.getByText('Lily: “The first thing he gave me that was only for me.”')).toBeTruthy();
    expect(screen.getByText("Lily hasn't said why yet.")).toBeTruthy();
    fireEvent.click(screen.getByRole('tab', { name: /Keepsakes/ }));
    const shelf = screen.getByRole('list', { name: 'Keepsakes' });
    expect(within(shelf).getAllByRole('listitem')).toHaveLength(2);
    expect(within(shelf).queryByText(/yc-application/)).toBeNull();
  });

  it('narrows the tab by title and path as you type', () => {
    render(<Shelves />);
    fireEvent.change(screen.getByLabelText('Find'), {
      target: { value: 'haven' },
    });
    const all = screen.getByRole('list', { name: 'All documents' });
    expect(within(all).getAllByRole('listitem')).toHaveLength(1);
    fireEvent.change(screen.getByLabelText('Find'), {
      target: { value: 'nothing like this' },
    });
    expect(screen.getByText(/No title or path here has/)).toBeTruthy();
  });

  it('searches the words, shows the passages for the tab, and opens one', () => {
    const onSearch = vi.fn();
    const onOpen = vi.fn();
    render(<Searched onSearch={onSearch} onOpen={onOpen} />);
    fireEvent.change(screen.getByLabelText('Find'), {
      target: { value: 'feeds' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Search the words' }));
    expect(onSearch).toHaveBeenCalledWith('feeds');
    const found = screen.getByRole('list', { name: 'In the words' });
    expect(within(found).getAllByRole('listitem')).toHaveLength(2);
    fireEvent.click(screen.getByRole('tab', { name: /Design/ }));
    const inDesign = screen.getByRole('list', { name: 'In the words' });
    expect(within(inDesign).getAllByRole('listitem')).toHaveLength(1);
    fireEvent.click(
      within(inDesign).getByRole('button', {
        name: 'The correspondence pipeline',
      }),
    );
    expect(onOpen).toHaveBeenCalledWith('design/correspondence-pipeline.md');
  });

  it('removes only scratch and your own, and only once the button has become its consequence', () => {
    const onRemove = vi.fn();
    render(<Shelves onRemove={onRemove} />);
    fireEvent.click(screen.getByRole('tab', { name: /Design/ }));
    expect(within(screen.getByRole('list', { name: 'Design' })).queryByRole('button', { name: 'Remove' })).toBeNull();
    fireEvent.click(screen.getByRole('tab', { name: /Scratch/ }));
    const scratch = screen.getByRole('list', { name: 'Scratch' });
    fireEvent.click(within(scratch).getByRole('button', { name: 'Remove' }));
    expect(onRemove).not.toHaveBeenCalled();
    fireEvent.click(
      within(scratch).getByRole('button', {
        name: 'Remove scratch/yc-application.md',
      }),
    );
    expect(onRemove).toHaveBeenCalledWith('scratch/yc-application.md');
  });

  it('adds a document of yours under human/, named safely', () => {
    const onAdd = vi.fn();
    render(<Shelves onAdd={onAdd} />);
    expect(screen.queryByRole('form', { name: 'Add a document of yours' })).toBeNull();
    fireEvent.click(screen.getByRole('tab', { name: /Yours/ }));
    const form = screen.getByRole('form', { name: 'Add a document of yours' });
    fireEvent.change(within(form).getByLabelText('Name'), {
      target: { value: 'my post' },
    });
    fireEvent.change(within(form).getByLabelText('Text'), {
      target: { value: 'Words.' },
    });
    fireEvent.click(within(form).getByRole('button', { name: 'Add human/my-post.md' }));
    expect(onAdd).toHaveBeenCalledWith('human/my-post.md', 'Words.');
    expect(humanPath('../etc/passwd')).toBeNull();
    expect(humanPath('notes.txt')).toBe('human/notes.txt');
  });

  it('opens a document and reads it whole', () => {
    render(<Reading />);
    expect(screen.getByText(/Feeds belong to communities/)).toBeTruthy();
  });

  // The shelf is the server's (seshat#35): reverse it and the tabs follow;
  // a kind it does not name comes last under its own name.
  it('orders and names its tabs by the shelf it is given, knowing no kind itself', () => {
    const shelf = [
      { kind: 'scratch', label: 'Temporary', position: 0 },
      { kind: 'design', label: 'Plans', position: 1 },
    ];
    render(<Shelves shelf={shelf} />);
    const tabs = screen.getAllByRole('tab').map((t) => t.textContent?.replace(/\d+$/, '').trim());
    expect(tabs.slice(0, 3)).toEqual(['All', 'Temporary', 'Plans']);
    expect(tabs).toContain('keepsake');
  });
});

