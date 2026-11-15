import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { registerWorker } from '../app/push';
import { App } from './App';
// Fonts bundled, not fetched: the server's CSP allows only its own origin,
// and a third-party font request on every load is a leak worth avoiding.
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import '@fontsource/jetbrains-mono/400.css';
import '@fontsource/jetbrains-mono/500.css';
import '@fontsource/newsreader/400.css';
import '@fontsource/newsreader/400-italic.css';
import '@fontsource/newsreader/500.css';
import './theme/contract.css';

// The service worker on every load, so a push can be shown whether or not
// the page is open (gaia#15). Only the retired entry (src/main.tsx) did
// this; the live one registered it only when notifications were turned on.
registerWorker();

createRoot(document.getElementById('root') as HTMLElement).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
