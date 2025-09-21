import { fileURLToPath, URL } from "url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import environment from "vite-plugin-environment";
import dotenv from "dotenv";
import viteCompression from "vite-plugin-compression";

dotenv.config();

export default defineConfig({
  root: "src/multi_frontend",
  build: {
    outDir: "../../dist",
    emptyOutDir: true,
    rollupOptions: {
      output: {
        manualChunks: {
          dfinity: [
            "@dfinity/agent",
            "@dfinity/candid",
            "@dfinity/principal",
            "@dfinity/auth-client",
          ],
          "react-vendor": ["react", "react-dom"],
        },
      },
    },
  },
  optimizeDeps: {
    esbuildOptions: {
      define: {
        global: "globalThis",
      },
    },
  },
  server: {
    watch: {
      usePolling: true, // Used to enable WSL HMR
      interval: 100,
    },
    proxy: {
      "/api": {
        target: "http://127.0.0.1:4943",
        changeOrigin: true,
      },
    },
  },
  plugins: [
    react(),
    environment("all", { prefix: "CANISTER_" }),
    environment("all", { prefix: "DFX_" }),
    viteCompression(),
  ],
  resolve: {
    alias: [
      {
        find: "declarations",
        replacement: fileURLToPath(
          new URL("../../src/declarations", import.meta.url),
        ),
      },
    ],
    extensions: [".js", ".ts", ".jsx", ".tsx"],
  },
});
