import type { ReactNode } from 'react';
import * as css from '../settings/settings.css';
import { ScrollArea } from '../shell/ScrollArea';

/** A house tab's page in the settings pages' column: the Charter's. */
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
