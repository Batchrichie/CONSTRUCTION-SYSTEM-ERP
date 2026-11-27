const { test, expect } = require('@playwright/test')

const baseURL = process.env.E2E_BASE_URL
const email = process.env.E2E_EMAIL
const password = process.env.E2E_PASSWORD

test.describe('authenticated company workspace', () => {
  test.skip(!baseURL || !email || !password, 'Set E2E_BASE_URL, E2E_EMAIL and E2E_PASSWORD to run authenticated browser tests.')

  test.beforeEach(async ({ page }) => {
    await page.goto('/')
    await expect(page.getByRole('heading', { name: 'Welcome back' })).toBeVisible()
    await page.getByLabel('Email address').fill(email)
    await page.getByLabel('Password').fill(password)
    await page.getByRole('button', { name: 'Sign in' }).click()
    await expect(page.getByRole('heading', { name: 'Good morning' })).toBeVisible({ timeout: 20_000 })
  })

  test('member can navigate core commercial and project screens', async ({ page }) => {
    await page.getByRole('link', { name: 'Projects', exact: true }).click()
    await expect(page).toHaveURL(/\/projects$/)
    await expect(page.getByRole('heading', { name: 'Projects', exact: true })).toBeVisible()

    await page.getByRole('link', { name: 'Customers & Suppliers', exact: true }).click()
    await expect(page).toHaveURL(/\/customers-suppliers$/)
    await expect(page.getByRole('heading', { name: 'Customers & Suppliers', exact: true })).toBeVisible()

    await page.getByRole('link', { name: 'Estimates & BOQ', exact: true }).click()
    await expect(page).toHaveURL(/\/estimates-boq$/)
    await expect(page.getByRole('heading', { name: 'Estimates & BOQ', exact: true })).toBeVisible()
  })

  test('member can end the authenticated session', async ({ page }) => {
    await page.getByRole('button', { name: 'Sign out' }).click()
    await expect(page.getByRole('heading', { name: 'Welcome back' })).toBeVisible()
    await expect(page.getByLabel('Email address')).toBeVisible()
  })
})
