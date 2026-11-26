import type { ReactNode } from 'react';
import type { Succession } from '../../api/types';
import * as settingsCss from '../settings/settings.css';
import * as css from './succession.css';

export function Chip({ kind, children }: { kind: keyof typeof css.chip; children: ReactNode }) {
  return <span className={css.chip[kind]}>{children}</span>;
}

/** A rule the page holds to, said once: the mocks' amber wall. */
export function Wall({ children }: { children: ReactNode }) {
  return (
    <p className={css.wall} role="note">
      {children}
    </p>
  );
}

/** The dry run's mark: on every page while the succession is a rehearsal. */
export function DryMark({ s }: { s: Succession | null | undefined }) {
  if (!s?.dry_run) return null;
  return (
    <span className={css.dry} title="A dry run: everything is real but the replacement, which is rehearsed on a copy and never touches her">
      Dry run
    </span>
  );
}

/**
 * A succession page's title row, under the app's top bar as every full
 * page has it: back to where it came from, the title with the dry-run
 * mark beside it, and its lede.
 */
export function PageHead({ title, lede, back, s }: { title: string; lede?: ReactNode; back: () => void; s: Succession | null | undefined }) {
  return (
    <>
      <button type="button" className={settingsCss.back} onClick={back}>
        ‹ Back
      </button>
      <div className={css.head}>
        <h1 className={settingsCss.title}>{title}</h1>
        <DryMark s={s} />
      </div>
      {lede && <p className={settingsCss.lede}>{lede}</p>}
    </>
  );
}

export function Row({ left, right }: { left: ReactNode; right?: ReactNode }) {
  return (
    <div className={css.row}>
      <span style={{ minWidth: 0 }}>{left}</span>
      {right}
    </div>
  );
}
