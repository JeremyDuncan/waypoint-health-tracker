const { test, expect } = require('@playwright/test');

// The form submission is cancelled inside the page, so this never erases the account
// it runs against. Do not swap this for page.route: WebKit sends the request from a
// page controlled by the service worker, where route interception does not see it.
test('clearing history needs a typed confirmation in the modal', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    window.clearSubmissions = [];
    window.addEventListener('submit', event => {
      if (!event.target.action.endsWith('/settings/history')) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      window.clearSubmissions.push(Object.fromEntries(new FormData(event.target)));
    }, true);
  });
  const submissions = () => page.evaluate(() => window.clearSubmissions);
  await page.goto('/session/new');
  await page.getByLabel('Email', { exact: true }).fill(process.env.TEST_EMAIL || 'demo@example.test');
  await page.getByLabel('Password', { exact: true }).fill(process.env.TEST_PASSWORD || 'synthetic-pass-123');
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();
  await page.goto('/settings');
  const open = page.getByRole('button', { name: 'Clear health history…', exact: true });
  const dialog = page.getByRole('dialog', { name: 'Clear all health history?' });
  const phrase = dialog.getByLabel('Type DELETE to confirm', { exact: true });
  const submit = dialog.getByRole('button', { name: 'Delete everything', exact: true });

  await open.click();
  await expect(dialog).toBeVisible();
  await expect(phrase).toBeFocused();
  await expect(submit).toBeDisabled();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
  await phrase.fill('delete');
  await expect(submit).toBeDisabled();
  await phrase.press('Enter');
  await phrase.fill('DELETE');
  await expect(submit).toBeEnabled();

  // Closing forgets the typed phrase, so reopening starts guarded again.
  await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(dialog).toBeHidden();
  await open.click();
  await expect(phrase).toHaveValue('');
  await expect(submit).toBeDisabled();
  expect(await submissions()).toEqual([]);

  await phrase.fill('DELETE');
  await submit.click();
  await expect.poll(submissions).toEqual([expect.objectContaining({ _method: 'delete', confirmation: 'DELETE' })]);
  expect(errors).toEqual([]);
});
