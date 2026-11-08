import { createContext, type ReactNode } from 'react';

// What the shell puts at the end of every screen's top bar, after the
// screen's own controls: the waiting badge (the approval queue). Nothing
// here by default, so a screen rendered alone (a story, a test) has none.
export const TopBarExtra = createContext<ReactNode>(null);
