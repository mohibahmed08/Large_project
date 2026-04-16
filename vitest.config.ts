//BASICALLY JUST SAYS RUN THE TEST FILES
//WITHIN "unit_tests" FOLDER CONTAINING .test.ts OR .spec.ts

import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: "jsdom",
    include: ["src/**/*.{test,spec}.{ts,tsx}"]
  }
});