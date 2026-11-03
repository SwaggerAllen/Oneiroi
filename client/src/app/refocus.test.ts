import { afterEach, describe, expect, it } from 'vitest';
import { onRefocus } from './refocus';

let visibility: DocumentVisibilityState = 'visible';
Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => visibility });

const setVisible = (v: DocumentVisibilityState) => {
  visibility = v;
  document.dispatchEvent(new Event('visibilitychange'));
};

describe('onRefocus', () => {
  let stop: () => void = () => undefined;
  afterEach(() => {
    stop();
    visibility = 'visible';
  });

  it('says the page is back, and for how long it was away, once per return', () => {
    let clock = 0;
    const seen: number[] = [];
    stop = onRefocus((away) => seen.push(away), () => clock);

    setVisible('hidden');
    clock = 45_000;
    setVisible('visible');
    // The focus that comes with the same return is the same return.
    window.dispatchEvent(new Event('focus'));
    expect(seen).toEqual([45_000]);

    // A window left for another and focused again.
    clock = 50_000;
    window.dispatchEvent(new Event('blur'));
    clock = 53_000;
    window.dispatchEvent(new Event('focus'));
    expect(seen).toEqual([45_000, 3_000]);
  });

  it('counts the network coming back and a page restored from the cache, and nothing while hidden', () => {
    let clock = 0;
    const seen: number[] = [];
    stop = onRefocus((away) => seen.push(away), () => clock);

    clock = 5_000;
    window.dispatchEvent(new Event('online'));
    clock = 10_000;
    window.dispatchEvent(Object.assign(new Event('pageshow'), { persisted: true }));
    clock = 15_000;
    window.dispatchEvent(Object.assign(new Event('pageshow'), { persisted: false }));
    expect(seen).toEqual([0, 0]);

    setVisible('hidden');
    clock = 20_000;
    window.dispatchEvent(new Event('focus'));
    expect(seen).toEqual([0, 0]);
  });

  it('stops listening when stopped', () => {
    const seen: number[] = [];
    onRefocus((away) => seen.push(away))();
    window.dispatchEvent(new Event('focus'));
    expect(seen).toEqual([]);
  });
});
