import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Linked } from './Linked';

describe('Linked (brain#90)', () => {
  it('renders the paths an ask names as links, and the rest as words', () => {
    render(<Linked text="Your read on design/p23-r1-domains-per-message.md and the human-correspondence/ folder" />);
    expect(screen.getByRole('link', { name: 'design/p23-r1-domains-per-message.md' }).getAttribute('href')).toBe('#/records/doc/design/p23-r1-domains-per-message.md');
    expect(screen.getByRole('link', { name: 'human-correspondence/' }).getAttribute('href')).toBe('#/records/dir/human-correspondence');
  });

  it('an ask with no path stays plain words', () => {
    const { container } = render(<Linked text="your word on two wordings" />);
    expect(container.textContent).toBe('your word on two wordings');
    expect(container.querySelector('a')).toBeNull();
  });
});
