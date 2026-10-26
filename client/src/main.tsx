import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './theme.css';
import { Swatch } from './tokens/Swatch';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Swatch />
  </StrictMode>,
);
