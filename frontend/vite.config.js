import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// In local dev (npm run dev), proxy /api to the backend container/service
export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
    proxy: {
      '/api': {
        target: process.env.VITE_API_PROXY_TARGET || 'http://localhost:5000',
        changeOrigin: true,
      },
    },
  },
});
