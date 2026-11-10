// Citations in her words (spec: `<slug>:<kind>/<ref>`, e.g.
// `lily:document/etymologies/oneiric.md`, `lily:bookmark/360`) become
// chips that open a peek. They are turned into markdown links on a
// private scheme before rendering, so the renderer stays stock.

const KINDS = 'document|bookmark|transcript|web|doc|letter|position|journal|soul|commitment|seed|habit|prediction|research|oracle';
const CITATION = new RegExp(`(?<![\\w/])([a-z][a-z0-9_-]*):(${KINDS})/([^\\s)\\]\`,;]+[^\\s)\\]\`,;.!?])`, 'g');

export interface Citation {
  slug: string;
  kind: string;
  ref: string;
}

export const CITE_SCHEME = 'cite:';

/** Wraps every citation outside code spans and fences as `[label](cite:slug:kind/ref)`. */
export function linkCitations(text: string): string {
  return text
    .split(/(```[\s\S]*?```|`[^`]*`)/)
    .map((part, i) =>
      i % 2 === 1
        ? part
        : part.replace(CITATION, (_m, slug: string, kind: string, ref: string) => `[${kind}/${ref}](${CITE_SCHEME}${slug}:${kind}/${ref})`),
    )
    .join('');
}

export function parseCite(href: string): Citation | null {
  if (!href.startsWith(CITE_SCHEME)) return null;
  const m = /^([^:]+):([^/]+)\/(.+)$/.exec(href.slice(CITE_SCHEME.length));
  return m ? { slug: m[1], kind: m[2], ref: m[3] } : null;
}
