import { test, expect } from '../fixtures/twoUsers'

test('two contexts boot independently into the signed-in app', async ({
  aliceContext,
  bobContext,
}) => {
  const alice = await aliceContext.newPage()
  const bob = await bobContext.newPage()

  await alice.goto('/settings')
  await bob.goto('/settings')

  // The Settings page hero renders once the Elm app has finished bootstrapping
  // from IndexedDB. Confirms each context is authenticated.
  await expect(alice.getByText('Local-first preferences')).toBeVisible({
    timeout: 30_000,
  })
  await expect(bob.getByText('Local-first preferences')).toBeVisible({
    timeout: 30_000,
  })
})

test('mock Resend responds to a sanity probe', async ({ resendMock }) => {
  expect(await resendMock.ping()).toBe(true)
})

test('CouchDB admin client can list databases', async ({ couchAdmin }) => {
  const dbs = await couchAdmin.allDbs()
  expect(Array.isArray(dbs)).toBe(true)
  expect(dbs).toEqual(expect.arrayContaining(['_users']))
})
