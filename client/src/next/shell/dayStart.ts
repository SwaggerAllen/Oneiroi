/** A YYYY-MM-DD day in this browser's zone as the instant it starts, `shift` days on (`to` is the next day's start, so the day itself is in). */
export function dayStart(day: string, shift: number): string | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return undefined;
  const [y, m, d] = day.split('-').map(Number);
  return new Date(y, m - 1, d + shift).toISOString();
}
