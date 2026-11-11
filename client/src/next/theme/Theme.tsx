import { assignInlineVars } from '@vanilla-extract/dynamic';
import type { ReactNode } from 'react';
import { useLayoutEffect } from 'react';
import { vars } from './contract.css';
import { DEFAULT_SEEDS, derive, type Seeds } from './derive';

/**
 * Applies a derived theme as CSS variables on the document root, so
 * everything sees it, including what React Aria portals out of the tree
 * (sheets, menus, dialogs). Set through the CSSOM, which the server's
 * CSP allows; a subject switch re-themes by calling this with new seeds.
 */
export function Theme({ seeds = DEFAULT_SEEDS, children }: { seeds?: Seeds; children: ReactNode }) {
  useLayoutEffect(() => {
    const assigned = assignInlineVars(vars, { color: derive(seeds).tokens }) as Record<string, string>;
    const root = document.documentElement.style;
    for (const [name, value] of Object.entries(assigned)) root.setProperty(name, value);
    return () => {
      for (const name of Object.keys(assigned)) root.removeProperty(name);
    };
  }, [seeds]);
  return <>{children}</>;
}
