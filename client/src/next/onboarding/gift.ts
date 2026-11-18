/** A gift the creation flow offers (spec §6.2): what it writes, and how. */
export interface Gift {
  key: string;
  title: string;
  writes: string[];
  guidance: string;
}

/** A resident's slug from her name: lowercase, hyphenated, two to forty characters, or empty. */
export function slugOf(name: string): string {
  const s = name
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^[^a-z]+/, '')
    .replace(/-+$/, '')
    .slice(0, 40);
  return s.length >= 2 ? s : '';
}
