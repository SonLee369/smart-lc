import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'clarinet', // This is the magic line
    globals: true,
  },
});