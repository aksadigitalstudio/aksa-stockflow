# Verification

Public demo: **https://aksa-stockflow.vercel.app/**

Source: https://github.com/aksadigitalstudio/aksa-stockflow

60 local test groups passed (20 domain, 8 PostgreSQL/PGlite, 22 browser workflow, 9 browser regression, 1 concurrent browser). On October 25, 2026, all **22 browser workflow groups** were repeated against the live Vercel deployment and passed. The public response was HTTP 200, JavaScript/CSS assets matched the tested local build, and no critical browser console errors occurred.

Critical public workflow: receive 100 → issue 10 → transfer 20 → A=70/B=20 → blind count 67 → recount 68 → explicit supervisor approval → exactly one -2 ledger adjustment → A=68. Refresh preserved the result.

The public app uses persistent browser-local Demo Mode. Supabase authentication, cloud data and Storage are prepared in source but are not enabled on this demo. Live Supabase credentials and physical camera hardware were not available for integration testing. Actual generated CSV contents and report PDF were verified; native OS download delivery is restricted by the managed test browser.

The earlier Sites source synchronization attempt was blocked by execution policy. Publication through the user-authorized GitHub and Vercel route is complete.
