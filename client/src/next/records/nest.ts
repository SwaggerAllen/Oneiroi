import type { LibraryDocument } from '../../api/types';
import { folderKey, sortDocs, type RecordsOrder } from './sort';

/**
 * A kind's documents as folders (the witness, 2026-11-12: "research needs
 * sub folders per research pass or else it's impossible to navigate"):
 * every path segment between the kind's folder and the file is a folder
 * of its own, so a research pass, a correspondent's thread or a wiki's
 * pages collapse under one row. Folders come before files at each level,
 * each in the chosen order.
 */
export interface Nest {
  name: string;
  /** The folder's path from the root, without a trailing slash. */
  path: string;
  folders: Nest[];
  files: LibraryDocument[];
  /** Every document under it, at any depth. */
  all: LibraryDocument[];
}

export function nest(docs: LibraryDocument[], order: RecordsOrder): Nest {
  const root = build('', '', docs.map((d) => ({ d, rest: d.path.split('/').slice(1) })), order);
  return root;
}

function build(name: string, path: string, items: Array<{ d: LibraryDocument; rest: string[] }>, order: RecordsOrder): Nest {
  const files: LibraryDocument[] = [];
  const groups = new Map<string, Array<{ d: LibraryDocument; rest: string[] }>>();
  for (const it of items) {
    if (it.rest.length <= 1) files.push(it.d);
    else groups.set(it.rest[0], [...(groups.get(it.rest[0]) ?? []), { d: it.d, rest: it.rest.slice(1) }]);
  }
  const folders = [...groups].map(([seg, sub]) => build(seg, path ? `${path}/${seg}` : seg, sub, order));
  folders.sort((a, b) => {
    if (order === 'name') return a.name.localeCompare(b.name);
    const ka = folderKey(a.all, order);
    const kb = folderKey(b.all, order);
    return (order === 'updated-oldest' ? ka - kb : kb - ka) || a.name.localeCompare(b.name);
  });
  return { name, path, folders, files: sortDocs(files, order), all: items.map((i) => i.d) };
}

/** A file's name within its folder. */
export function leaf(d: LibraryDocument): string {
  return d.path.split('/').pop() ?? d.path;
}
