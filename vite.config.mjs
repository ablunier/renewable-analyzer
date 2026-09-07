import { defineConfig } from "vite";
import elmPlugin from "vite-plugin-elm";
import tailwindcss from "@tailwindcss/vite";

function fixElmHmrEmptyDependencyList() {
  return {
    name: "fix-elm-hmr-empty-dependency-list",
    apply: "serve",
    transform(code, id) {
      if (!id.endsWith(".elm") || !code.includes("import.meta.hot")) return null;
      const patched = code.replace(
        /import\.meta\.hot\.accept\(\[\s*""\s*\]/,
        "import.meta.hot.accept([]",
      );
      return patched === code ? null : { code: patched, map: null };
    },
  };
}

export default defineConfig({
  plugins: [elmPlugin(), fixElmHmrEmptyDependencyList(), tailwindcss()],

  server: {
    proxy: {
      "/api": {
        target: "http://localhost:8000",
        changeOrigin: false,
      },
    },
  },
});
