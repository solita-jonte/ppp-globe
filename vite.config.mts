import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  root: 'src/Frontend',
  build: {
    outDir: resolve(__dirname, 'src/Frontend/dist'),
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(__dirname, 'src/Frontend/index.html')
    }
  }
});
