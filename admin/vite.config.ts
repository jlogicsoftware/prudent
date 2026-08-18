import react from "@vitejs/plugin-react";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const here = dirname(fileURLToPath(import.meta.url));
// The framework admin scaffold is imported from source (not a pnpm dependency edge): this app
// owns the single copy of react/react-admin, dedupe collapses any duplicate, and the repo root
// stays language-neutral. This is the TypeScript analog of the Dart path-dep into client/
// (CLAUDE.md "Target structure") and the Java empty-<relativePath/> parent (ADR-001).
const scaffoldEntry = resolve(here, "../../jZen/admin/src/index.ts");
const repoRoot = resolve(here, "..");
const jzenRoot = resolve(here, "../../jZen");

// Backend target for the dev proxy. Prudent's server runs on 8085 (ADR-010), not Quarkus dev's
// default 8080 — that value is a collision avoided against jZen's own local stack.
const backend = `http://localhost:${process.env.ZEN_APP_PORT ?? "8085"}`;

export default defineConfig(({ command }) => ({
  // Served at /admin/ same-origin with the API in production (the built bundle is staged under
  // the server's META-INF/resources/admin), so asset URLs must be /admin/-relative. Dev keeps
  // base "/" so the dev server and its /api proxy stay at http://localhost:5173.
  base: command === "build" ? "/admin/" : "/",
  plugins: [react()],
  resolve: {
    alias: {
      "@jzen/admin-core": scaffoldEntry,
    },
    dedupe: ["react", "react-dom", "react-admin", "ra-data-simple-rest"],
  },
  server: {
    port: 5173,
    // Serve the scaffold source, which lives outside this app's root in the sibling checkout.
    fs: { allow: [repoRoot, jzenRoot] },
    // Same-origin proxy so the httpOnly zen_access_token cookie flows without CORS juggling.
    proxy: {
      "/api": backend,
      "/openapi": backend,
    },
  },
}));
