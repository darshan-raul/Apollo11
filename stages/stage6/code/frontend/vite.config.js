import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  base: '/',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  define: {
    'import.meta.env.VITE_IDENTITY_URL': JSON.stringify('http://localhost:8080'),
    'import.meta.env.VITE_FLIGHT_URL': JSON.stringify('http://localhost:8081'),
    'import.meta.env.VITE_BOOKING_URL': JSON.stringify('http://localhost:8082'),
    'import.meta.env.VITE_SEARCH_URL': JSON.stringify('http://localhost:8083'),
  },
})