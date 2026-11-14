const { defineConfig, devices } = require('@playwright/test');
module.exports = defineConfig({
  testDir: './test/browser', outputDir: './test/artifacts', fullyParallel: false, workers: 1,
  timeout: 45000, use: { baseURL: process.env.BASE_URL || 'http://127.0.0.1:3100', trace: 'retain-on-failure' },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 1000 } } },
    { name: 'iphone', use: { ...devices['iPhone 13'], defaultBrowserType: 'webkit' } }
  ]
});
