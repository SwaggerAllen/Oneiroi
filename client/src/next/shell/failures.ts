/** A turn that failed (brain#88, #89): it sorts first in the bell and turns its dot red. */
export const isFailure = (e: { kind: string }) => e.kind === 'provider_credits' || e.kind === 'turn_failed';
