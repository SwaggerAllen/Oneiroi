import type { ReactNode } from 'react';
import { ScrollArea } from '../shell/ScrollArea';
import * as css from '../settings/settings.css';

/** A house tab's page: the same column the settings pages use. */
export function HousePage({ label, title, lede, children }: { label: string; title: string; lede: string; children: ReactNode }) {
  return (
    <ScrollArea label={label}>
      <div className={css.page}>
        <h1 className={css.title}>{title}</h1>
        <p className={css.lede}>{lede}</p>
        {children}
      </div>
    </ScrollArea>
  );
}
