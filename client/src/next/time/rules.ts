// Rhythm's pure parts: what a time, a window and an hour count look like,
// and the zones offered.

// The bound sunna#22 sets: free time is one to four slots a day.
export const SLOTS = 4;

export const isTime = (t: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(t);

/** A waking window, "HH:MM-HH:MM". */
export function isWindow(w: string): boolean {
  const [from, to, ...rest] = w.split('-');
  return rest.length === 0 && from !== undefined && to !== undefined && isTime(from) && isTime(to);
}

/** Rounds' cadence: whole hours, 0 is off. */
export const isHours = (h: string) => /^\d{1,2}$/.test(h.trim());

/** Free time after moving one slot: the same list with that slot's time changed, never shorter. */
export function moveSlot(times: string[], from: string, to: string): string[] {
  return times.map((t) => (t === from ? to : t));
}

/** Whether a slot may be added: under the bound and not already there. */
export const canAddSlot = (times: string[], t: string) => isTime(t) && times.length < SLOTS && !times.includes(t);

export function deviceZone(): string | null {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
  } catch {
    return null;
  }
}

/** Every zone the browser knows, with the current one and the device's always in it. */
export function allZones(current: string, device: string | null, known?: string[]): string[] {
  let list = known;
  if (!list) {
    try {
      list = (Intl as unknown as { supportedValuesOf?: (key: string) => string[] }).supportedValuesOf?.('timeZone') ?? [];
    } catch {
      list = [];
    }
  }
  return [...new Set([current, ...(device ? [device] : []), ...list])].sort();
}
