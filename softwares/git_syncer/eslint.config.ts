import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";
import { defineConfig } from "eslint/config";

export default defineConfig([
  {
    files: ["**/*.{js,mjs,cjs,ts,mts,cts}"], plugins: { js }, extends: ["js/recommended"], languageOptions: { globals: globals.node }, rules: {
      // eslint-disable-next-line @typescript-eslint/naming-convention
      "@typescript-eslint/naming-convention": "warn",
      // eslint-disable-next-line @typescript-eslint/naming-convention
      "no-console": "warn",
    }
  },
  tseslint.configs.recommended,
  // tseslint.configs.stylistic,
]);


// function abc(a: any) {

// }
