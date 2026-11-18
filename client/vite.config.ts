/// <reference types="vitest/config" />
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin';
import react from '@vitejs/plugin-react';
import { resolve } from 'node:path';
import { defineConfig } from 'vite';

// The built client is served by Phoenix from priv/static/client, so the
// base is the mount point rather than the site root. One client, at
// index.html, with next.html kept as an alias for links made before the
// switch (design/ui-build.md); the old client is gone (2026-11-18).
export default defineConfig({
  plugins: [react(), vanillaExtractPlugin()],
  base: '/client/',
  build: {
    outDir: '../priv/static/client',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(import.meta.dirname, 'index.html'),
        next: resolve(import.meta.dirname, 'next.html'),
      },
    },
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
