import { useShell } from '../state/store';
import * as css from './records.css';

/**
 * Back, kept at the top of a record however far down it is read (the
 * witness, 2026-11-17: "the back arrow to fix to the top of the screen").
 * One step back, named for where it goes, and, when that is not already
 * the root, straight to Records: his "<- records … <previous page>",
 * the light version first, without the "…" of further steps.
 */
export function BackBar({ onBack }: { onBack: () => void }) {
  const stack = useShell((s) => s.stacks.records);
  const go = useShell((s) => s.go);
  const previous = stack.length > 1 ? stack[stack.length - 2] : '';

  return (
    <nav className={css.backBar} aria-label="Back">
      <button type="button" className={css.backStep} onClick={onBack}>
        ‹ {placeName(previous)}
      </button>
      {previous !== '' && (
        <button type="button" className={css.backRoot} onClick={() => go({ tab: 'records', path: '' })}>
          Records
        </button>
      )}
    </nav>
  );
}

/** A stack entry as the reader would name it: the record's or folder's last part. */
export function placeName(path: string): string {
  if (path === '') return 'Records';
  const [kind, ...rest] = path.split('/');
  const last = rest.filter(Boolean).pop() ?? kind;
  const name = last.replace(/\.md$/, '').replace(/[-_]+/g, ' ');
  if (kind === 'history') return `History of ${name}`;
  return name;
}
