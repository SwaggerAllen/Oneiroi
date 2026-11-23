import { createContext, useContext } from 'react';
import type { Live } from './live';

/** The one socket's Live, for a page that joins a channel of its own (the house's, sunna#80). */
export const LiveContext = createContext<Live | null>(null);

export const useLive = () => useContext(LiveContext);
