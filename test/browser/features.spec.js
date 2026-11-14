const { test, expect } = require('@playwright/test');
// On narrow screens the main navigation lives behind the menu button.
async function navigate(page, name) {
  const menu = page.getByRole('button', { name: 'Menu', exact: true });
  if (await menu.isVisible()) await menu.click();
  await page.getByRole('navigation', { name: 'Main navigation' }).getByRole('link', { name, exact: true }).click();
}

test('weekly review, target and maintenance goals, rolling trend, appointment PDF and backup status', async ({ page }, testInfo) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  // Carry forward appearance choices saved before the rename.
  await page.addInitScript(() => {
    if (!localStorage.getItem('waypoint-health.theme')) localStorage.setItem('hearth.theme', 'dark');
  });
  await page.goto('/session/new');
  await expect(page).toHaveTitle('Waypoint Health · Personal health');
  await expect(page.getByRole('link', { name: 'Waypoint Health home', exact: true })).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  const manifest = await (await page.request.get('/manifest')).json();
  expect(manifest.name).toBe('Waypoint Health');
  expect(manifest.icons[0].src).toBe('/waypoint-icon-192.png');
  await page.getByLabel('Email', { exact: true }).fill(process.env.TEST_EMAIL || 'demo@example.test');
  await page.getByLabel('Password', { exact: true }).fill(process.env.TEST_PASSWORD || 'synthetic-pass-123');
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  for (const [date, value] of [['2026-11-09T08:00', '200'], ['2026-11-10T08:00', '195'], ['2026-11-12T08:00', '190']]) {
    await page.getByRole('link', { name: '＋ Log weight', exact: true }).click();
    await page.getByRole('spinbutton', { name: 'Weight', exact: true }).fill(value);
    await page.getByLabel('Unit', { exact: true }).selectOption('lb');
    await page.getByLabel('Weighed at').fill(date);
    await page.getByRole('button', { name: 'Save weight', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();
  }
  await page.goto('/journal/2026-11-13');
  await page.getByLabel('Day notes', { exact: true }).fill('Appointment browser note café 🌿');
  await page.getByRole('button', { name: 'Save journal', exact: true }).click();
  await page.goto('/review?week=2026-11-09');
  await expect(page.getByRole('heading', { name: 'Your weekly review.' })).toBeVisible();
  await expect(page.getByText('Appointment browser note café 🌿', { exact: true })).toBeVisible();
  await expect(page.locator('[aria-label="Weekly summary"]')).toContainText('195.0 lb');
  await page.screenshot({ path: `test/artifacts/${testInfo.project.name}-review.png`, fullPage: true });
  await navigate(page, 'Goals');
  await page.getByRole('button', { name: /^(Set|Edit) goal$/ }).click();
  await page.getByLabel('Goal type').selectOption('target');
  await page.getByLabel('Goal unit').selectOption('lb');
  await page.getByLabel('Target weight', { exact: true }).fill('180');
  await page.getByLabel('Start date', { exact: true }).fill('2026-11-09');
  await page.getByRole('button', { name: 'Save goal', exact: true }).click();
  await expect(page.getByRole('progressbar')).toHaveAttribute('value', '50.0');
  await expect(page.locator('.milestone-list li.reached')).toHaveCount(2);
  await page.locator('.milestone-list li.reached a').first().click();
  await expect(page).toHaveURL(/journal\/2026-11-10$/);
  await page.goto('/goal');
  await page.getByRole('button', { name: 'Appearance', exact: true }).click();
  await page.getByRole('menuitemradio', { name: 'Dark', exact: true }).click();
  await page.screenshot({ path: `test/artifacts/${testInfo.project.name}-goals-dark.png`, fullPage: true });
  await page.getByRole('button', { name: 'Edit goal', exact: true }).click();
  await page.getByLabel('Goal type').selectOption('maintenance');
  await expect(page.getByLabel('Target weight', { exact: true })).toBeHidden();
  await page.getByLabel('Lower weight').fill('189');
  await page.getByLabel('Upper weight').fill('192');
  await page.getByRole('button', { name: 'Save goal', exact: true }).click();
  await expect(page.locator('.goal-progress')).toContainText('Within your range');
  await page.goto('/?range=custom&from=2026-11-09&to=2026-11-14');
  await page.getByLabel('7-day trend', { exact: true }).check();
  for (const mode of ['raw', 'weekly', 'monthly']) {
    await page.getByRole('combobox', { name: 'View', exact: true }).selectOption(mode);
    await expect(page.locator('[data-timeline-target="explanation"]')).toContainText('preceding 168 hours');
    const series = await page.locator('[data-controller="timeline"]').evaluate(element => {
      const chart = Chart.getChart(element.querySelector('canvas'));
      return { actual: chart.data.datasets[1].data, expected: JSON.parse(element.dataset.timelinePayloadValue).trend };
    });
    expect(series.actual).toEqual(series.expected);
  }
  await page.getByLabel('Weight', { exact: true }).uncheck();
  await expect(page.getByLabel('7-day trend', { exact: true })).toBeChecked();
  await page.getByRole('button', { name: 'Appearance', exact: true }).click();
  await page.getByRole('menuitemradio', { name: 'Light', exact: true }).click();
  await page.screenshot({ path: `test/artifacts/${testInfo.project.name}-rolling-trend.png`, fullPage: true });
  await page.goto('/report?range=custom&from=2026-11-09&to=2026-11-14');
  await expect(page.locator('.report-preview')).not.toContainText('Appointment browser note');
  await page.getByLabel('Include written journal and injection notes').check();
  await page.getByRole('button', { name: 'Update preview' }).click();
  await expect(page.locator('.report-preview')).toContainText('Appointment browser note café 🌿');
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('link', { name: '↓ Download PDF', exact: true }).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe('waypoint-health-appointment-2026-11-09-2026-11-14.pdf');
  const path = `test/artifacts/${testInfo.project.name}-appointment.pdf`;
  await download.saveAs(path);
  expect(require('node:fs').readFileSync(path).subarray(0, 5).toString()).toBe('%PDF-');
  await page.screenshot({ path: `test/artifacts/${testInfo.project.name}-report.png`, fullPage: true });
  await navigate(page, 'Settings');
  await expect(page.getByLabel('Server backup status', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
  expect(errors).toEqual([]);
});
