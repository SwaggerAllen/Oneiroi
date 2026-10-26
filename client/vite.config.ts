/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// The built client is served by Phoenix from priv/static/client, so the
// base is the mount point rather than the site root.
export default defineConfig({
  plugins: [react()],
  base: '/client/',
  build: { outDir: '../priv/static/client', emptyOutDir: true },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
