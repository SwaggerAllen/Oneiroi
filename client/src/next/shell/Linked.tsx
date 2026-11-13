import { pieces } from './paths';

/** An ask's words with the repo paths it names as links (brain#90). */
export function Linked({ text, className, onOpen }: { text: string; className?: string; onOpen?: () => void }) {
  const parts = pieces(text);
  // No path named: the words as they are, one text node.
  if (!parts.some((p) => 'path' in p)) return <>{text}</>;
  return (
    <>
      {parts.map((p, i) =>
        'path' in p ? (
          <a key={i} className={className} href={p.href} onClick={onOpen}>
            {p.path}
          </a>
        ) : (
          <span key={i}>{p.text}</span>
        ),
      )}
    </>
  );
}
