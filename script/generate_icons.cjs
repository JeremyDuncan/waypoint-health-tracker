#!/usr/bin/env node
// Development-only: npm ci, then node script/generate_icons.cjs.
// Render the code-native SVG once; the app serves the bundled PNGs without Node.
const { chromium } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const root = path.resolve(__dirname, '..', 'public');
  const svg = fs.readFileSync(path.join(root, 'waypoint-icon.svg'), 'utf8');
  const browser = await chromium.launch();
  try {
    for (const size of [192, 512]) {
      const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
      await page.setContent(`<style>html,body{margin:0;background:transparent}svg{display:block;width:100%;height:100%}</style>${svg}`);
      await page.screenshot({ path: path.join(root, `waypoint-icon-${size}.png`), omitBackground: true });
      await page.close();
      fs.copyFileSync(path.join(root, `waypoint-icon-${size}.png`), path.join(root, `icon-${size}.png`));
    }
    fs.copyFileSync(path.join(root, 'waypoint-icon-512.png'), path.join(root, 'icon.png'));
    fs.copyFileSync(path.join(root, 'waypoint-icon.svg'), path.join(root, 'icon.svg'));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
