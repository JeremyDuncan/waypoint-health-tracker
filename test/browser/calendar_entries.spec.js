const { test, expect } = require('@playwright/test');

test('a calendar day adds weight, injections and notes, and shots can be compared', async ({ page }, testInfo) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/session/new');
  await page.getByLabel('Email', { exact: true }).fill(process.env.TEST_EMAIL || 'demo@example.test');
  await page.getByLabel('Password', { exact: true }).fill(process.env.TEST_PASSWORD || 'synthetic-pass-123');
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();

  const dialog = page.getByRole('dialog', { name: 'Calendar day' });
  const openDay = async date => {
    await page.locator(`[data-calendar-date="${date}"]`).click();
    await expect(dialog.getByRole('link', { name: '＋ Weight', exact: true })).toBeVisible();
  };
  const addWeight = async (date, value) => {
    await openDay(date);
    await dialog.getByRole('link', { name: '＋ Weight', exact: true }).click();
    await expect(dialog.getByLabel('Weighed at')).toHaveValue(`${date}T12:00`);
    await dialog.getByRole('spinbutton', { name: 'Weight', exact: true }).fill(value);
    await dialog.getByLabel('Unit', { exact: true }).selectOption('lb');
    await dialog.getByRole('button', { name: 'Save weight', exact: true }).click();
    await expect(dialog).toBeHidden();
    await expect(page.locator(`[data-calendar-date="${date}"] .calendar-weight`)).toBeVisible();
  };
  const addShot = async (date, dose, site) => {
    await openDay(date);
    await dialog.getByRole('link', { name: '＋ Injection', exact: true }).click();
    await dialog.getByLabel('Dose (mg)', { exact: true }).selectOption(dose);
    await dialog.getByLabel('Site (optional)').selectOption(site);
    await dialog.getByRole('button', { name: 'Save injection', exact: true }).click();
    await expect(dialog).toBeHidden();
    await expect(page.locator(`[data-calendar-date="${date}"] .calendar-injection`)).toBeVisible();
  };

  await page.goto('/calendar?month=2026-10');
  // The dialog keeps working when reopened on the same day and after stepping back from a form.
  await openDay('2026-10-01');
  await dialog.getByRole('link', { name: '＋ Weight', exact: true }).click();
  await dialog.getByRole('link', { name: '← Oct 1', exact: true }).click();
  await expect(dialog.getByRole('heading', { name: 'Thursday, October 1, 2026' })).toBeVisible();
  await dialog.getByRole('button', { name: 'Close day' }).click();
  await openDay('2026-10-01');
  await page.screenshot({ path: `test/artifacts/${testInfo.project.name}-calendar-day.png` });
  await dialog.getByRole('button', { name: 'Close day' }).click();

  await addWeight('2026-10-01', '210');
  await addShot('2026-10-01', '2.5', 'Thigh');
  await addWeight('2026-10-05', '208.5');
  await addShot('2026-10-08', '2.5', 'Abdomen');
  await addWeight('2026-10-08', '207.5');
  await addWeight('2026-10-12', '206');
  await addShot('2026-10-15', '5', 'Upper arm');
  await addWeight('2026-10-15', '205');
  await addWeight('2026-10-19', '205.6');
  await openDay('2026-10-20');
  // Already expanded when an earlier run left a note on this day.
  const notes = dialog.locator('details');
  if (!await notes.evaluate(element => element.open)) await notes.locator('summary').click();
  await dialog.getByLabel('Day notes', { exact: true }).fill('Logged from the calendar');
  await dialog.getByRole('button', { name: 'Save journal', exact: true }).click();
  await expect(dialog).toBeHidden();
  await expect(page.locator('[data-calendar-date="2026-10-20"] .calendar-journal')).toBeVisible();
  const chipColor = date => page.locator(`[data-calendar-date="${date}"] .calendar-injection`).first().evaluate(chip => getComputedStyle(chip).borderTopColor);
  expect(await chipColor('2026-10-01')).toBe(await chipColor('2026-10-08'));
  expect(await chipColor('2026-10-01')).not.toBe(await chipColor('2026-10-15'));
  await page.screenshot({ path: `test/artifacts/${testInfo.project.name}-calendar-doses.png`, fullPage: true });

  await page.goto('/injections?range=custom&from=2026-10-01&to=2026-10-31&mode=aligned&site=all&side=all&dose=all');
  const key = page.getByRole('list', { name: 'Compared shots' }).getByRole('button');
  const lines = () => page.locator('[data-injection-insights-target="trajectory"]').evaluate(canvas => Chart.getChart(canvas).data.datasets.map(line => ({ base: line.baseColor, color: line.borderColor, width: line.borderWidth, shape: line.pointStyle })));
  const before = await lines();
  expect(await key.count()).toBe(before.length);
  // Every line is distinguishable, even when several share a dose.
  expect(new Set(before.map(line => line.base)).size).toBe(before.length);
  await expect(key.first()).toContainText('Oct 15 · 5 mg');
  await page.locator('section[aria-labelledby="trajectory-heading"]').screenshot({ path: `test/artifacts/${testInfo.project.name}-shot-comparison.png` });
  await key.first().click();
  await expect(key.first()).toHaveAttribute('aria-pressed', 'true');
  const after = await lines();
  expect(after.at(-1).width).toBe(4);
  expect(after[0].color).not.toBe(after[0].base);
  await page.locator('section[aria-labelledby="trajectory-heading"]').screenshot({ path: `test/artifacts/${testInfo.project.name}-shot-comparison-selected.png` });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
  expect(errors).toEqual([]);
});

test.describe('slow or failed requests', () => {
  // Routing cannot see requests from a page the service worker controls in WebKit.
  test.use({ serviceWorkers: 'block' });

  test.beforeEach(async ({ page }) => {
    await page.goto('/session/new');
    await page.getByLabel('Email', { exact: true }).fill(process.env.TEST_EMAIL || 'demo@example.test');
    await page.getByLabel('Password', { exact: true }).fill(process.env.TEST_PASSWORD || 'synthetic-pass-123');
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();
    await page.goto('/calendar?month=2026-09');
  });

  const openNotes = async dialog => {
    const notes = dialog.locator('details');
    await expect(notes).toBeVisible();
    if (!await notes.evaluate(element => element.open)) await notes.locator('summary').click();
    return dialog.getByLabel('Day notes', { exact: true });
  };

  test('another day is never left editable while a day loads or after it fails', async ({ page }) => {
    const dialog = page.getByRole('dialog', { name: 'Calendar day' });
    const day = date => page.locator(`[data-calendar-date="${date}"]`);
    let release;
    const held = new Promise(resolve => { release = resolve; });
    await page.route('**/calendar/2026-09-02', async route => { await held; await route.abort(); });
    await day('2026-09-01').click();
    await (await openNotes(dialog)).fill('Draft for September 1');
    await dialog.getByRole('button', { name: 'Close day' }).click();
    await day('2026-09-02').click();
    await expect(dialog).toContainText('Loading…');
    await expect(dialog.locator('form')).toHaveCount(0);
    release();
    await expect(dialog).toContainText('Couldn’t load this');
    await expect(dialog.locator('form')).toHaveCount(0);
    await page.unroute('**/calendar/2026-09-02');
    await dialog.getByRole('button', { name: 'Close day' }).click();
    await day('2026-09-02').click();
    await expect(dialog.getByRole('heading', { name: 'Wednesday, September 2, 2026' })).toBeVisible();
  });

  for (const outcome of ['saved', 'NOT saved']) {
    test(`a late save that was ${outcome} keeps the next day's draft`, async ({ page }) => {
      const dialog = page.getByRole('dialog', { name: 'Calendar day' });
      const day = date => page.locator(`[data-calendar-date="${date}"]`);
      let release;
      const held = new Promise(resolve => { release = resolve; });
      await page.route('**/journal/2026-09-03', async route => { await held; await (outcome === 'saved' ? route.continue() : route.abort()); });
      await day('2026-09-03').click();
      await (await openNotes(dialog)).fill('Saved slowly');
      await dialog.getByRole('button', { name: 'Save journal', exact: true }).click();
      await dialog.getByRole('button', { name: 'Close day' }).click();
      await day('2026-09-04').click();
      await expect(dialog.getByRole('heading', { name: 'Friday, September 4, 2026' })).toBeVisible();
      const draft = await openNotes(dialog);
      await draft.fill('Unsaved draft');
      release();
      await expect(dialog.locator('.flash')).toContainText(`earlier entry was ${outcome}`);
      await expect(draft).toHaveValue('Unsaved draft');
    });
  }
});
