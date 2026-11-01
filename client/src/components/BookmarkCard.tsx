import type { Bookmark } from '../api/types';
import { ActorChip } from './ActorChip';
import { Button } from './Button';
import { TagChip } from './TagChip';

// A row shows when, who bookmarked, who pinned, the span, the tags, and
// whether the index holds it now, as the server says (spec §6.3,
// kumbukumbu #38), with when a turn last listed it as a fact beside that.
// The line and the summary are the resident's words and no control
// edits them.
export function BookmarkCard({
  bookmark,
  residentName,
  inIndex = false,
  onPin,
  onUnpin,
  onOpen,
}: {
  bookmark: Bookmark;
  residentName: string;
  inIndex?: boolean;
  onPin?: (number: number) => void;
  onUnpin?: (number: number) => void;
  onOpen?: (bookmark: Bookmark) => void;
}) {
  const pinned = bookmark.pinned_at !== null;
  const day = bookmark.anchor_at.slice(0, 10);
  const span = bookmark.turns_back === 1 ? 'one turn' : `${bookmark.turns_back} turns`;
  return (
    <article
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-2)',
        padding: 'var(--space-3) 0',
        borderBottom: '1px solid var(--hairline)',
      }}
    >
      <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'baseline' }}>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--ink-faint)' }}>
          #{bookmark.number}
        </span>
        <p style={{ margin: 0, fontFamily: 'var(--font-serif)', fontSize: 17, lineHeight: '24px', flex: 1 }}>
          {bookmark.line}
        </p>
        {pinned ? <span style={{ fontSize: 12, color: 'var(--witness)' }}>pinned</span> : null}
        {inIndex ? <span style={{ fontSize: 12, color: 'var(--ink-faint)' }}>in the index</span> : null}
      </div>
      {bookmark.summary ? (
        <p style={{ margin: 0, fontSize: 15, lineHeight: '22px', color: 'var(--ink-muted)' }}>{bookmark.summary}</p>
      ) : null}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 'var(--space-2)', alignItems: 'center', fontSize: 13 }}>
        <span style={{ color: 'var(--ink-faint)' }}>
          {day}, {span}
        </span>
        <ActorChip actor={bookmark.added_by} name={residentName} />
        {bookmark.proposed_by ? <span style={{ color: 'var(--ink-faint)' }}>proposed by you</span> : null}
        {bookmark.pinned_by ? (
          <span style={{ color: 'var(--ink-faint)' }}>
            pinned by {bookmark.pinned_by.kind === 'witness' ? 'you' : residentName}
          </span>
        ) : null}
        {bookmark.last_indexed_at ? (
          <span style={{ color: 'var(--ink-faint)' }}>last listed in a turn {bookmark.last_indexed_at.slice(0, 10)}</span>
        ) : null}
        {bookmark.tags.map((tag) => (
          <TagChip key={tag} slug={tag} />
        ))}
      </div>
      <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
        {onOpen ? (
          <Button variant="quiet" onClick={() => onOpen(bookmark)}>
            Open the moment
          </Button>
        ) : null}
        {pinned && onUnpin ? (
          <Button onClick={() => onUnpin(bookmark.number)}>Unpin</Button>
        ) : null}
        {!pinned && onPin ? <Button onClick={() => onPin(bookmark.number)}>Pin</Button> : null}
      </div>
    </article>
  );
}
