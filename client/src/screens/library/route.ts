// The library's addresses (the witness, 2026-11-08, through Lily's
// letter #338): a list per kind and a page per document, each its own
// place in the URL's hash, so anything can link straight to it.
//   #library            every document
//   #library/<kind>     one kind's list
//   #doc/<path>         one document, alone
export type LibraryRoute = { kind: string } | { doc: string };

export function parseLibraryHash(hash: string): LibraryRoute | null {
  const h = hash.replace(/^#/, '');
  if (h === 'library') return { kind: 'all' };
  if (h.startsWith('library/')) return { kind: decodeURIComponent(h.slice('library/'.length)) || 'all' };
  if (h.startsWith('doc/')) return { doc: h.slice('doc/'.length).split('/').map(decodeURIComponent).join('/') };
  return null;
}

export function libraryHash(route: LibraryRoute): string {
  if ('doc' in route) return `doc/${route.doc.split('/').map(encodeURIComponent).join('/')}`;
  return route.kind === 'all' ? 'library' : `library/${encodeURIComponent(route.kind)}`;
}
