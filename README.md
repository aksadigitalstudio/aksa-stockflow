# AKSA StockFlow

**[Open the public demo](https://aksa-stockflow.vercel.app/)** · [Source repository](https://github.com/aksadigitalstudio/aksa-stockflow)

The published demo stores data in each visitor’s browser; cloud authentication is not enabled.

A functional inventory and physical stock-count workspace for **Aruna Mart**. React + Vite, with a transactional IndexedDB demo and an optional authenticated Supabase backend. No backend credentials are needed to try it.

## Run the included build

Requires Node.js 22.18 or newer:

```sh
node server.mjs
```

Open **http://127.0.0.1:4500/**. The delivery archive includes `dist/`, so viewing the built app does not require dependency installation.

To edit or rebuild:

```sh
npm ci
npm run dev
npm run build
npm run preview
```

The default mode clearly identifies itself as **Demo Mode**. It creates 48 realistic products, four categories, two locations, three suppliers, stock movements, receipts, issues, a completed transfer, an in-transit transfer and an adjusted sample stock count. Demo records are stored only in this browser's IndexedDB. They are not shared between devices. Browser clearing can remove them; Settings offers an explicit JSON backup download. CSV exports cover the operational datasets. Backup JSON is an archival download, not a supported restore/import format.

## What works

- Product creation/editing/archive, unique SKU and barcode validation, optimized uploaded photos, categories, suppliers and location management.
- Base units: pieces, packs, boxes, bottles, kilograms and meters. Product-specific packaging conversion factors are copied into each document; changing a factor does not rewrite history. Base units are locked after the first movement.
- Multi-line stock receipt and issue documents with a review step, supplier, cost, reason, reference, date and notes.
- Transfers: **Draft → In Transit → Completed**, plus confirmed cancellation. Dispatch removes source stock; receipt adds destination stock once. Cancelling an in-transit transfer explicitly records the return to source.
- Ledger-derived current stock, minimum-stock alerts and chronological stock cards. No manually editable balance field. Invalid quantities and negative stock are rejected.
- Scoped, per-location stock counts: draft, fixed snapshot at start, blind entry, barcode/SKU lookup, clearly selected replacement/increment scanning, progress, submission, variance review, requested recount, original entry history, explicit supervisor approval and one-time ledger adjustment.
- Included SKUs are locked at the counted location until adjustment/cancellation. Incoming in-transit transfers must first be received/cancelled. Unrelated SKUs and other locations remain available. This deliberately avoids ambiguous mid-count stock movements.
- Significant differences meet either the configured absolute quantity or percentage threshold. Approval then requires a supervisor/owner to type **APPROVE VARIANCE**. Changes from zero expected stock count as 100%.
- Manual signed adjustments require an authorized role, reason, note and explicit confirmation.
- Date-filtered reports, CSV exports, validated CSV import with template/preview and all-or-nothing commit, print-friendly reports and append-only audit history.
- Phone-friendly blind-count cards, optional camera barcode decoding with `BarcodeDetector`, and reliable text/USB-scanner fallback. Camera availability depends on browser support, secure context and permission; declining permission does not block the workflow.

## Financial and quantity definitions

The single configuration module is `src/config.js`. App identity, initial business identity, locations, base units, count thresholds and visual tokens originate there. Settings may update the business display name, valuation currency and variance thresholds. The initial valuation currency is **IDR**, editable in Settings; changing it does not perform foreign-exchange conversion.

Inventory value is **current quantity × current recorded purchase cost**. This is an operational estimate, not FIFO, weighted-average accounting, historical valuation or profit. Count variance value uses the purchase cost captured at the snapshot. Products without cost are excluded from valuation. Aggregated quantities are labelled as mixed base units and should not be treated as a single physical measurement.

## Demo permissions

The header's demo role selector demonstrates owner, admin, warehouse staff, assigned stock counter, supervisor and viewer permissions. Counters see assigned sessions and no ledger/cost data; blind expected quantities are omitted from their pre-submission projection. Supervisors/owners approve and adjust. Viewers cannot write.

**Demo role switching is not authentication or a security boundary.** Anyone with this browser's developer tools can access local demo records. Do not store sensitive real inventory in a publicly accessible demo device. Production mode requires the backend below and removes demo identity switching.

## Enable the Supabase backend

Use a dedicated Supabase project. No privileged key belongs in `.env`, Git or the browser build.

1. Run `supabase/schema.sql` once in the Supabase SQL editor. It creates the `stockflow` schema, relational records/line items, ledger, normalized count entries, profiles, audit records, a private image bucket and service-only RPCs. Tables have RLS and no direct anon/authenticated access. The initial cloud workspace is empty, with the two configured locations; demo records are not copied to cloud.
2. Create staff accounts through Supabase Auth. Provision each account's UUID in `stockflow.profiles`, for example:

   ```sql
   insert into stockflow.profiles(id,name,role)
   values ('AUTH-USER-UUID-HERE','Your staff name','OWNER');
   ```

   Provision other accounts with an appropriate role from the schema. This workspace is for one business per Supabase project. It does not claim multi-tenant organization isolation.
3. Run `npm run prepare:backend`. This copies the exact UI command reducer/configuration into `supabase/functions/_shared/` so the server uses the same inventory rules.
4. Link the project with the Supabase CLI and deploy `stockflow`:

   ```sh
   supabase functions deploy stockflow
   supabase secrets set STOCKFLOW_ALLOWED_ORIGINS=https://your-deployment.example
   ```

   Multiple exact origins can be comma-separated. For local cloud testing, include `http://127.0.0.1:4500`. The function uses Supabase's automatically provided server-side URL and service-role key. Its gateway `verify_jwt` setting is false because **the function itself verifies every token with `auth.getUser()`** and requires an active provisioned profile before any read/write. No request can choose its own actor or role.
5. Create `.env.local` using `.env.example`, with only the Supabase project URL and client-safe anon/publishable key. Rebuild the app. Staff sign-in replaces Demo Mode. Both values must be configured together.

The Edge Function reads the authoritative state, validates a command against the authenticated profile, and commits with a database revision lock. Concurrent conflicts retry against fresh data. All affected ledger/document/count rows commit in one PostgreSQL transaction. Unique SKU/barcode, nonnegative balances, immutable ledger checks and unique per-count adjustment constraints add database enforcement. A client cannot call the privileged RPCs or private tables directly.

Uploaded product images use private Supabase Storage and signed read URLs. The UI compresses to WebP; cloud writes upload via the authenticated server, not a public bucket policy. The two client-safe environment values are not service credentials.

## Deploy as a static app

For Vercel, import the project, use **Vite**, build command `npm run build` and output directory **dist**. For another static host, upload `dist/`. `vercel.json` and hash navigation support refreshable workspace routes. No paid APIs or external image/font assets are needed. Leave Supabase variables unset for a browser-local demo.

## Verification

```sh
npm test
npm run test:database
# Start the app in a second terminal first:
npm run test:browser
npm run test:regression
npm run test:concurrency
```

Browser tests use installed Chrome through Playwright. `TEST_BASE_URL` can target a deployed static demo for the main browser suite. Test data is isolated in fresh browser contexts.

Verified groups:

- 20 domain groups: uniqueness, quantities, negative-stock rejection, atomic rollback, packaging history, idempotency, location locks, blind projection, snapshot stability, original/recount history, approval, one-time adjustment, cancellation/returns, CSV, roles and serialized ledger validation.
- 8 PostgreSQL/PGlite groups: schema compilation, empty cloud workspace, stock posting, transfer consistency, normalized count entries, reconciliation uniqueness, concurrent revision conflicts, ledger immutability and denial of direct authenticated table/RPC access.
- 22 browser workflow groups: create/upload/edit product, locations, receive 100 → issue 10 → transfer 20, stock card, blind count 67 → recount 68, supervisor approval → one -2 movement, exports, reports/print, permissions, persistence and responsive layouts.
- 9 browser regression groups: category/supplier forms, repeated scans, active mobile counting, typed significant-variance approval, reconciliation, manual adjustment, scanner fallback, global search and runtime errors.

- 1 concurrent-browser group: simultaneous receipts from two tabs preserve both quantities, documents and unique references.

The browser workflow's resulting balance is **Location A: 68; Location B: 20; exactly one opname adjustment movement**. Screenshot evidence, generated report PDF, verified CSV bytes and machine-readable results are in `test-artifacts/` in the local workspace. Tests do not certify real camera hardware or a live Supabase deployment; cloud Auth/Storage/Edge deployment needs project credentials and its own deployment smoke test. The native OS download handoff is restricted by the managed test browser; export contents are independently inspected from the generated browser blob.
