// Playwright 配置：浏览器冒烟（CI 的 playwright job 用）
// 本地运行：npm install && npx playwright test
const { defineConfig, devices } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "./e2e",
  timeout: 90_000,
  expect: { timeout: 20_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [["list"]],
  use: {
    headless: true,
    baseURL: "http://127.0.0.1:8123",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "python -m http.server 8123 --directory deploy/monolith-web",
    port: 8123,
    reuseExistingServer: true,
    timeout: 30_000,
  },
});
