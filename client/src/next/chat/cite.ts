// Citations (spec §3.3, F26; Oneiroi.Seshat.Citations): `<slug>:<kind>/<ref>`.
// A record kind (bookmark, position, …) names a record; any other kind is
// a shelf, and the citation names the document `<kind>/<ref>` (`.md` when
// the ref has no extension; keepsakes, root files and goals sit at the
// root). Only the resident's own slug is a citation here: another
// resident's never resolves (sharing is not built), and requiring the
// slug keeps ordinary "word:word/word" text from turning into chips.
// They become markdown links on a private scheme before rendering, so the
// renderer stays stock.

export const RECORD_KINDS = new Set([
  'bookmark',
  'position',
  'prediction',
  'date',
  'figure',
  'transcript',
  'habit',
  'seed',
  'soul',
  'commitment',
  'web',
  'doc',
]);

const ROOT_KINDS = new Set(['keepsake', 'root', 'goals']);

export interface Citation {
  slug: string;
  kind: string;
  ref: string;
}

export const CITE_SCHEME = 'cite:';

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function pattern(slug: string): RegExp {
  // The server's own grammar (citations.ex), for this resident's slug.
  return new RegExp(`(?<![\\w/:])(${escape(slug)}):([a-z][a-z0-9-]*)\\/([A-Za-z0-9_-](?:[A-Za-z0-9_./#:-]*[A-Za-z0-9_-])?)`, 'g');
}

/** Wraps every citation outside code spans and fences as `[kind/ref](cite:slug:kind/ref)`. */
export function linkCitations(text: string, slug: string): string {
  const re = pattern(slug);
  return text
    .split(/(```[\s\S]*?```|`[^`]*`)/)
    .map((part, i) =>
      i % 2 === 1 ? part : part.replace(re, (_m, s: string, kind: string, ref: string) => `[${kind}/${ref}](${CITE_SCHEME}${s}:${kind}/${ref})`),
    )
    .join('');
}

export function parseCite(href: string): Citation | null {
  if (!href.startsWith(CITE_SCHEME)) return null;
  const m = /^([^:]+):([^/]+)\/(.+)$/.exec(href.slice(CITE_SCHEME.length));
  return m ? { slug: m[1], kind: m[2], ref: m[3] } : null;
}

/** The document a shelf citation names, or null for a record kind. */
export function documentPath(c: Pick<Citation, 'kind' | 'ref'>): string | null {
  if (RECORD_KINDS.has(c.kind)) return null;
  const ref = c.ref.split('#')[0];
  const name = /\.[A-Za-z0-9]+$/.test(ref) ? ref : `${ref}.md`;
  return ROOT_KINDS.has(c.kind) ? name : `${c.kind}/${name}`;
}

/** The citation targets a document is cited by: with and without `.md`. */
export function targetsFor(slug: string, path: string): string[] {
  const [first, ...rest] = path.split('/');
  const kind = rest.length ? first : 'root';
  const ref = rest.length ? rest.join('/') : path;
  const bare = ref.replace(/\.md$/, '');
  return [...new Set([`${slug}:${kind}/${ref}`, `${slug}:${kind}/${bare}`])];
}
