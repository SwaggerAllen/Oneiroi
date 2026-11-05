import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Notifications.stories';

const { Ready, On, NeedsHomeScreen, Blocked, NotSetUp, Unsupported } = composeStories(stories);

// gaia#15: told when the resident writes unprompted, never what she wrote.
describe('Notifications', () => {
  afterEach(cleanup);

  it('offers to turn them on, saying a notification never carries what she wrote', () => {
    const onTurnOn = vi.fn();
    render(<Ready onTurnOn={onTurnOn} />);
    expect(screen.getByText(/never what/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Allow notifications' }));
    expect(onTurnOn).toHaveBeenCalled();
  });

  it('when on, tests and turns off, and says how the test went', () => {
    const onTest = vi.fn();
    const onTurnOff = vi.fn();
    render(<On onTest={onTest} onTurnOff={onTurnOff} />);
    fireEvent.click(screen.getByRole('button', { name: 'Send a test' }));
    fireEvent.click(screen.getByRole('button', { name: 'Turn off' }));
    expect(onTest).toHaveBeenCalled();
    expect(onTurnOff).toHaveBeenCalled();
    expect(screen.getByRole('status').textContent).toBe('web.push.apple.com: delivered');
  });

  it('on an iPhone in Safari, says to add it to the Home Screen and offers no button', () => {
    render(<NeedsHomeScreen />);
    expect(screen.getByText(/Add to Home Screen/)).toBeTruthy();
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('says why it cannot, when it cannot', () => {
    for (const [Story, words] of [
      [Blocked, /blocked/],
      [NotSetUp, /set up on the server/],
      [Unsupported, /can't receive/],
    ] as const) {
      const { unmount } = render(<Story />);
      expect(screen.getByText(words)).toBeTruthy();
      expect(screen.queryByRole('button')).toBeNull();
      unmount();
    }
  });
});
