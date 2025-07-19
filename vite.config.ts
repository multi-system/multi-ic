import { defineConfig } from 'vite';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    testTimeout: 30000,
    slowTestThreshold: 2000,
    bail: 1,
    threads: false, // Run tests sequentially within files
    reporters: ['verbose'],
  },
  resolve: {
    alias: {
      '@': '/src',
    },
  },
});
