import { formatHash } from '../state/routes';

/**
 * The repo paths an ask names, found so they can be links (brain#90; the
 * witness, 2026-11-13: "the queue clears faster when he can open what
 * he's reviewing"). A path has a folder and either ends in `/` (a folder)
 * or a file extension; a URL, a fraction or "and/or" is not one.
 */
const PATH = /(?<![\w/.:@-])((?:[A-Za-z0-9_][A-Za-z0-9_.-]*\/)+(?:[A-Za-z0-9_][A-Za-z0-9_.-]*\.(?:md|markdown|txt|json|ya?ml|html|css|exs?|tsx?|jsx?|csv))?)(?![\w/])/g;

export type Piece = { text: string } | { path: string; href: string };

/** Where a path opens: a file in Records' viewer, a folder in Records' tree with it opened. */
export function hrefOf(path: string): string {
  return path.endsWith('/') ? formatHash({ tab: 'records', path: `dir/${path.slice(0, -1)}` }) : formatHash({ tab: 'records', path: `doc/${path}` });
}

/** The text cut into plain runs and paths; a "path" with no extension that doesn't end in `/` stays text. */
export function pieces(text: string): Piece[] {
  const out: Piece[] = [];
  let last = 0;
  for (const m of text.matchAll(PATH)) {
    const path = m[1];
    const isFolder = path.endsWith('/');
    const isFile = /\.[A-Za-z]+$/.test(path);
    if (!isFolder && !isFile) continue;
    const at = m.index ?? 0;
    if (at > last) out.push({ text: text.slice(last, at) });
    out.push({ path, href: hrefOf(path) });
    last = at + path.length;
  }
  if (last < text.length) out.push({ text: text.slice(last) });
  return out;
}
