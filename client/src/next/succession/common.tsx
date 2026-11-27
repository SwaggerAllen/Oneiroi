import type { ReactNode } from 'react';
import type { Succession } from '../../api/types';
import * as settingsCss from '../settings/settings.css';
import * as css from './succession.css';
import { useShell } from '../state/store';
import { useGo } from './hooks';
import { nextOf } from './logic';

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
 * Back, the overview from any page (the witness, 2026-11-26: keep the
 * process in view) in the middle, and Next to the next step reached
 * (2026-11-27): the row every succession page opens with.
 */
export function PageNav({ back, s, home = true }: { back: () => void; s: Succession | null | undefined; home?: boolean }) {
  const go = useGo();
  const path = useShell((x) => x.pagePath);
  const next = nextOf(path, s);
  return (
    <nav className={css.nav} aria-label="Succession pages">
      <button type="button" className={settingsCss.back} onClick={back}>
        ‹ Back
      </button>
      {home ? (
        <button type="button" className={settingsCss.back} onClick={() => go('')}>
          Succession home
        </button>
      ) : (
        <span />
      )}
      <span className={css.navEnd}>
        {next && (
          <button type="button" className={settingsCss.back} onClick={() => go(next.page)} aria-label={`Next: ${next.name}`}>
            Next ›
          </button>
        )}
      </span>
    </nav>
  );
}

/**
 * A succession page's title row, under the app's top bar as every full
 * page has it: its nav row, the title with the dry-run mark beside it,
 * and its lede.
 */
export function PageHead({ title, lede, back, s, home = true }: { title: string; lede?: ReactNode; back: () => void; s: Succession | null | undefined; home?: boolean }) {
  return (
    <>
      <PageNav back={back} s={s} home={home} />
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
