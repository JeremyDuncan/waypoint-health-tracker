const { test, expect } = require('@playwright/test');
// On narrow screens the main navigation lives behind the menu button.
async function navigate(page, name) {
  const menu = page.getByRole('button', { name: 'Menu', exact: true });
  if (await menu.isVisible()) await menu.click();
  await page.getByRole('navigation', { name: 'Main navigation' }).getByRole('link', { name, exact: true }).click();
}
const email = process.env.TEST_EMAIL || 'demo@example.test';
const password = process.env.TEST_PASSWORD || 'synthetic-pass-123';
const login = async page => {
  await page.goto('/session/new');
  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Password', { exact: true }).fill(password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();
};
test('quick logging, actual events, weekly mode, journal, filters and offline retry', async ({ page }, testInfo) => {
  const errors = [];
  const externalRequests = [];
  page.on('request', request => { if (new URL(request.url()).origin !== new URL(testInfo.project.use.baseURL || process.env.BASE_URL || 'http://127.0.0.1:3100').origin) externalRequests.push(request.url()); });
  page.on('console', message => { if (message.type() === 'error' && /Content Security Policy|Failed to register controller/.test(message.text())) errors.push(message.text()); });
  page.on('pageerror', error => errors.push(error.message));
  await login(page);
  await page.getByRole('link', { name: '＋ Log weight', exact: true }).click();
  await page.getByRole('spinbutton', { name: 'Weight', exact: true }).fill('208.4');
  await page.getByLabel('Unit', { exact: true }).selectOption('lb');
  await page.getByLabel('Weighed at').fill('2026-11-02T00:05');
  await page.getByRole('button', { name: 'Save weight', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();
  await page.getByRole('link', { name: '＋ Log weight', exact: true }).click();
  await page.getByRole('spinbutton', { name: 'Weight', exact: true }).fill('94.3');
  await page.getByLabel('Unit', { exact: true }).selectOption('kg');
  await page.getByLabel('Weighed at').fill('2026-11-02T08:20');
  await page.getByRole('button', { name: 'Save weight', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();
  await page.getByRole('link', { name: '＋ Log injection', exact: true }).click();
  await page.getByLabel('Dose (mg)', { exact: true }).selectOption('5');
  await page.getByLabel('Site (optional)').selectOption('Thigh');
  await page.getByLabel('Side (optional)').selectOption('Left');
  await page.getByLabel('Actually injected at').fill('2026-11-03T09:30');
  await page.getByLabel('Notes (optional)').fill('Synthetic browser injection');
  await page.getByRole('button', { name: 'Save injection', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();
  await page.goto('/journal/2026-11-04');
  await page.getByLabel('Day notes', { exact: true }).fill('Synthetic journal 🌿');
  await page.getByRole('button', { name: 'Save journal', exact: true }).click();
  await expect(page.getByRole('status').filter({ hasText: 'Journal saved.' })).toBeVisible();
  await page.goto('/?range=custom&from=2026-11-02&to=2026-11-04&mode=raw&trend=false&weight=true&injections=true&notes=true');
  await expect(page.locator('.event-marker.injection').first()).toBeVisible();
  await expect(page.locator('.event-marker.journal').first()).toBeVisible();
  const injectionCount = await page.locator('.event-marker.injection').count();
  await page.getByRole('combobox', { name: 'View', exact: true }).selectOption('weekly');
  await expect(page.locator('.event-marker.injection')).toHaveCount(injectionCount);
  await expect(page.locator('[data-timeline-target="explanation"]')).toContainText('Average per Monday–Sunday week');
  await page.getByRole('combobox', { name: 'View', exact: true }).selectOption('monthly');
  await expect(page.locator('[data-timeline-target="explanation"]')).toContainText('Average per calendar month');
  await expect(page.locator('.event-marker.injection')).toHaveCount(injectionCount);
  await expect(page.locator('.event-marker.journal').first()).toBeVisible();
  const monthly = await page.locator('[data-controller="timeline"]').evaluate(element => {
    const payload = JSON.parse(element.dataset.timelinePayloadValue);
    const chart = Chart.getChart(element.querySelector('canvas'));
    return { actual: chart.data.datasets[0].data, expected: payload.monthly, datasets: chart.data.datasets.length };
  });
  expect(monthly.actual).toEqual(monthly.expected);
  expect(monthly.datasets).toBe(1);
  await page.getByLabel('7-day trend', { exact: true }).check();
  await expect(page.locator('.event-marker.injection')).toHaveCount(injectionCount);
  await expect(page.locator('.event-marker.journal').first()).toBeVisible();
  expect(await page.locator('[data-timeline-target="canvas"]').evaluate(canvas => Chart.getChart(canvas).data.datasets.length)).toBe(2);
  await page.getByLabel('7-day trend', { exact: true }).uncheck();
  await page.getByLabel('Injections', { exact: true }).uncheck();
  await expect(page.locator('[data-timeline-target="injectionRow"]')).toBeHidden();
  await page.getByLabel('Injections', { exact: true }).check();
  await expect(page.getByRole('button', { name: 'Zoom in', exact: true })).toHaveCount(0);
  await page.screenshot({ path: `test/artifacts/${testInfo.project.name}-timeline.png`, fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBeTruthy();
  await page.locator('.event-marker.injection').first().click();
  await expect(page).toHaveURL(/journal\/2026-11-03/);
  await expect(page.locator('.day-event:has(.type-pill.injection)').first()).toContainText('5.0 mg');
  await page.locator('.day-event').filter({ hasText: 'Synthetic browser injection' }).first().getByRole('link', { name: 'Edit injection →' }).click();
  await expect(page.getByLabel('Notes (optional)')).toHaveValue('Synthetic browser injection');
  await page.getByRole('link', { name: '← Back to overview' }).click();
  await page.getByRole('link', { name: '＋ Log weight', exact: true }).click();
  await expect(page.getByLabel('Unit', { exact: true })).toHaveValue('kg');
  await page.getByRole('spinbutton', { name: 'Weight', exact: true }).fill('93.25');
  await page.getByLabel('Weighed at').fill('2026-11-05T08:00');
  await page.context().setOffline(true);
  await page.getByRole('button', { name: 'Save weight', exact: true }).click();
  await expect(page.locator('.save-status')).toContainText('NOT been saved');
  await expect(page.getByRole('spinbutton', { name: 'Weight', exact: true })).toHaveValue('93.25');
  await page.context().setOffline(false);
  await page.getByRole('button', { name: 'Save weight', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();
  expect(errors).toEqual([]);
  expect(externalRequests).toEqual([]);
});
test('CSV mapping preview and duplicate-safe commit', async ({ page }) => {
  await login(page);
  await navigate(page, 'Settings');
  await page.getByLabel('File type').selectOption('csv');
  await page.getByLabel('UTF-8 file').setInputFiles('docs/examples/weights.csv');
  await page.getByRole('button', { name: 'Upload & preview' }).click();
  await expect(page.getByRole('heading', { name: 'Map your weight CSV' })).toBeVisible();
  await page.getByRole('button', { name: 'Validate & preview rows' }).click();
  await expect(page.getByRole('heading', { name: 'Import preview' })).toBeVisible();
  await expect(page.locator('.import-counts')).toContainText('0 conflicts');
  await expect(page.locator('p.errors')).toHaveCount(0);
  // Repeat runs against the same account have nothing left to import.
  const nothingNew = page.getByRole('button', { name: 'Nothing new to import' });
  const importNew = page.getByRole('button', { name: /^Import \d+ new entr(y|ies)$/ });
  await expect(nothingNew.or(importNew)).toBeVisible();
  if (await nothingNew.isVisible()) {
    await expect(nothingNew).toBeDisabled();
  } else {
    await importNew.click();
    await expect(page.getByRole('heading', { name: 'Your settings.' })).toBeVisible();
  }
});
