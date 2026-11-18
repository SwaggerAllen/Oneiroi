// A name for a document of yours: letters, digits, dashes, underscores,
// with .md added when it has no extension.
export function humanPath(name: string, folder?: string | null): string | null {
  const plain = name.trim().replace(/\s+/g, '-');
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$/.test(plain)) return null;
  const file = /\.(md|txt)$/i.test(plain) ? plain : `${plain}.md`;
  // A witness's documents go in the folder named for them (seshat#81).
  return folder ? `human/${folder}/${file}` : `human/${file}`;
}
