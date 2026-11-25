const { test, expect } = require('@playwright/test');

test('main navigation collapses into an accessible menu on phones and stays inline on desktop', async ({ page, isMobile }, testInfo) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/session/new');
  // No menu for signed-out visitors.
  await expect(page.getByRole('button', { name: 'Menu', exact: true })).toHaveCount(0);
  await page.getByLabel('Email', { exact: true }).fill(process.env.TEST_EMAIL || 'demo@example.test');
  await page.getByLabel('Password', { exact: true }).fill(process.env.TEST_PASSWORD || 'synthetic-pass-123');
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your health, over time.' })).toBeVisible();

  const menu = page.getByRole('button', { name: 'Menu', exact: true });
  const nav = page.getByRole('navigation', { name: 'Main navigation' });

  if (!isMobile) {
    await expect(menu).toBeHidden();
    await expect(nav.getByRole('link', { name: 'Calendar', exact: true })).toBeVisible();
    expect(errors).toEqual([]);
    return;
  }

  await expect(menu).toBeVisible();
  await expect(nav).toBeHidden();
  await expect(menu).toHaveAttribute('aria-expanded', 'false');

  await menu.click();
  const close = page.getByRole('button', { name: 'Close menu', exact: true });
  await expect(close).toHaveAttribute('aria-expanded', 'true');
  await expect(nav.getByRole('link', { name: 'Overview', exact: true })).toBeFocused();
  await expect(nav.getByRole('link', { name: 'Overview', exact: true })).toHaveClass(/active/);
  await expect(nav.getByRole('button', { name: 'Sign out', exact: true })).toBeVisible();
  for (const link of await nav.getByRole('link').all()) expect((await link.boundingBox()).height).toBeGreaterThanOrEqual(44);
  await page.screenshot({ path: `test/artifacts/${testInfo.project.name}-navigation-menu.png` });

  await page.keyboard.press('Escape');
  await expect(nav).toBeHidden();
  await expect(menu).toBeFocused();

  await menu.click();
  await page.mouse.click(200, 700);
  await expect(nav).toBeHidden();

  await menu.click();
  await nav.getByRole('link', { name: 'Calendar', exact: true }).click();
  await expect(page).toHaveURL(/\/calendar$/);
  await expect(nav).toBeHidden();
  await expect(menu).toHaveAttribute('aria-expanded', 'false');
  await menu.click();
  await expect(nav.getByRole('link', { name: 'Calendar', exact: true })).toHaveClass(/active/);
  await page.keyboard.press('Escape');

  // Opening the menu partway down a page keeps the header and menu in view, without moving the page.
  await page.goto('/settings');
  await page.evaluate(() => window.scrollTo(0, 600));
  await menu.click();
  expect((await page.locator('.site-header').boundingBox()).y).toBeCloseTo(0, 0);
  await expect(nav.getByRole('link', { name: 'Overview', exact: true })).toBeInViewport();
  expect(await page.evaluate(() => Math.round(window.scrollY))).toBe(600);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
  expect(errors).toEqual([]);
});
