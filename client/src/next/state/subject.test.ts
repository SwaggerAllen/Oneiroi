import { afterEach, describe, expect, it, vi } from 'vitest';
import { settled } from './subject';

describe('a subject switch waits for the new view (2026-11-23)', () => {
  afterEach(() => vi.unstubAllGlobals());

  // Frames run one at a time, by hand.
  const frames = () => {
    const queue: FrameRequestCallback[] = [];
    vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => queue.push(cb));
    return () => queue.shift()?.(0);
  };

  it('rises only once nothing has been fetching for a few frames', () => {
    const step = frames();
    let fetching = 2;
    const done = vi.fn();
    settled(done, () => fetching, () => 0);
    step();
    step();
    expect(done).not.toHaveBeenCalled();
    fetching = 0;
    step();
    step();
    expect(done).not.toHaveBeenCalled();
    step();
    expect(done).toHaveBeenCalledOnce();
  });

  it('never waits past its bound on a read that does not settle', () => {
    const step = frames();
    let t = 0;
    const done = vi.fn();
    settled(done, () => 1, () => t);
    step();
    t = 5000;
    step();
    expect(done).toHaveBeenCalledOnce();
  });
});
