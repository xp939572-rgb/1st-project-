# Saba Muzaffer Kayani — Consultation Booking & Payment System

Converts the existing single-page site into a booking system with a fixed
**PKR 1,500** consultation fee and server-verified PayFast payment.

---

## ⚠️ Before you read anything else: the one open item

PayFast's **public** developer docs (`https://gopayfast.com/docs/`) only
describe their **API-based** integration — where *your server* receives the
customer's raw card number/CVV or bank account/CNIC and forwards it to
PayFast. That's a real PayFast product, but it means your infrastructure
would fall under **PCI-DSS compliance scope**, and it directly contradicts
what you asked for (payment credentials handled by PayFast, not by this
site).

What you actually want is PayFast's **hosted/redirect checkout**
("PayFast Checkout" / "Payment Links") — confirmed to exist, but its exact
integration contract (session-creation endpoint, required fields, redirect
URL, and the signature scheme used to verify the return) isn't published in
the public docs. PayFast provides this to merchants directly, typically once
your merchant account is approved.

**What this means practically:**

- Everything in this system is complete and production-ready **except one
  function**: `initiateHostedCheckout()` in `lib/payfast.js`. It currently
  throws a clear error instead of pretending to work.
- `getTransactionStatus()` in the same file **is** fully implemented against
  PayFast's documented API and does the real server-side payment
  verification — this is the part that matters most for security, and it's
  done.
- To finish the integration: contact your PayFast account/integration
  contact, ask for the **hosted checkout** integration spec, and fill in
  `initiateHostedCheckout()` accordingly. Nothing else in the system needs
  to change — `api/create-payment.js` already calls it and expects a
  `{ redirectUrl }` back.
- Until then, set `PAYMENT_MODE=mock` in a **non-production** environment to
  test the entire booking flow (validation, database, emails, success/fail
  pages) with a fake checkout page instead of real PayFast. See "Sandbox /
  Mock Testing" below.

---

## What was changed

| File | Change |
|---|---|
| `public/index.html` | Your existing site, unchanged except: added `<link>` to `booking.css`, added the booking modal markup + `<script src="/js/booking.js">` before `</body>`, and changed the two "Book a Consultation" buttons to open the modal instead of scrolling to the old contact form. The general contact form further down the page is untouched and still works as a separate inquiry form. |
| `public/css/booking.css` | New — styles for the modal and result pages, using the same color/type tokens as the existing site. |
| `public/js/booking.js` | New — modal open/close, client-side UX validation, calls the booking + payment APIs. |
| `public/success.html` `failed.html` `cancelled.html` | New — post-payment result pages. |
| `public/mock-checkout.html` | New — **testing only**, simulates PayFast when `PAYMENT_MODE=mock`. |
| `api/create-booking.js` | New — validates input, creates a `PENDING_PAYMENT` booking with the server-fixed price. |
| `api/create-payment.js` | New — starts the PayFast checkout for an existing booking. Price is re-read from the database row, never from the request. |
| `api/payfast-return.js` | New — where PayFast/the browser returns after checkout. Re-verifies the transaction server-side before marking anything as paid. Idempotent. |
| `api/booking-status.js` | New — lets `success.html`/`failed.html` fetch non-sensitive booking details to display. |
| `lib/*.js` | New — validation, database, email, PayFast adapter, mock payment adapter, booking ID generator. |
| `schema.sql` | New — Postgres schema, including a `CHECK (amount = 1500)` constraint. |
| `.env.example`, `vercel.json`, `package.json` | New — configuration. |

Nothing about the visual design, animations, typography, sections, images,
navigation, or branding was touched beyond wiring the two CTA buttons to the
new modal.

---

## Required npm packages

```
pg
```
(Only one runtime dependency — `pg` for Postgres. Email uses `fetch`
directly against Resend's HTTP API, so no SDK is required. Node 18+ on
Vercel has `fetch` built in.)

Install locally:
```bash
npm install
```

---

## Required Vercel Environment Variables

Set these in **Vercel → Project Settings → Environment Variables** (not in
any committed file):

| Variable | Description |
|---|---|
| `PAYFAST_MERCHANT_ID` | From your PayFast merchant account |
| `PAYFAST_SECURED_KEY` | From your PayFast merchant account — **secret** |
| `PAYFAST_BASE_URL` | PayFast API base URL (sandbox and production URLs differ — confirm both with PayFast) |
| `PAYMENT_MODE` | `sandbox` \| `production` \| `mock` (mock is blocked automatically when `VERCEL_ENV=production`) |
| `EMAIL_API_KEY` | Resend API key |
| `EMAIL_FROM` | A verified sending address, e.g. `Saba Muzaffer Kayani <bookings@yourdomain.com>` |
| `BOOKING_NOTIFICATION_EMAIL` | `Sabamuzaffar9@gmail.com` — where new paid-booking notifications go |
| `DATABASE_URL` | Postgres connection string |
| `SITE_URL` | Your production URL, e.g. `https://sabamuzafferkayani.com`. **Required in production** — no longer falls back to the request's Host header (see Security Checklist) |
| `UPSTASH_REDIS_REST_URL` | From an Upstash Redis database — powers rate limiting |
| `UPSTASH_REDIS_REST_TOKEN` | From the same Upstash database — **secret** |

Set each for the **Production**, **Preview**, and **Development**
environments in Vercel as appropriate — e.g. use `PAYMENT_MODE=mock` and a
sandbox database for Preview, `PAYMENT_MODE=production` only for Production.

---

## Database Setup

1. Provision a Postgres database. Any of these work fine at this scale:
   - **Vercel Postgres** (simplest if you're already on Vercel)
   - **Neon** (neon.tech — generous free tier)
   - **Supabase**
2. Run the schema once:
   ```bash
   psql "$DATABASE_URL" -f schema.sql
   ```
3. Add `DATABASE_URL` to Vercel's environment variables.

The schema stores only: `booking_id, full_name, email, phone,
appointment_date, appointment_time, consultation_type, description, amount,
currency, payment_status, booking_status, payfast_transaction_id,
created_at, updated_at`. No card numbers, CVVs, PINs, or passwords are ever
stored — the system never receives them in the first place.

---

## Email Setup (Resend)

1. Create a Resend account (resend.com).
2. Verify a sending domain (or use their onboarding subdomain for early
   testing — check current Resend docs, this may have changed).
3. Create an API key, add it as `EMAIL_API_KEY` in Vercel.
4. Set `EMAIL_FROM` to an address on your verified domain.
5. Set `BOOKING_NOTIFICATION_EMAIL=Sabamuzaffar9@gmail.com`.

Every paid booking sends two emails:
- **To the customer** — "Consultation Booking Confirmed — PKR 1,500", with
  booking ID, date, time, consultation type, payment status.
- **To `Sabamuzaffar9@gmail.com`** — "New Paid Consultation — [Booking ID]",
  with name, email, phone, date, time, consultation type, amount, payment
  status, transaction ID.

Emails are only sent once per booking — `payfast-return.js` only sends them
on the first transition to `PAID`, never on a replayed/duplicate callback.

---

## Local Development

```bash
npm install
cp .env.example .env
# fill in .env with sandbox/dev values — never real production secrets
vercel dev
```

`vercel dev` runs both the static site and the `/api` functions locally,
matching production behavior.

### Testing the booking form
1. Open the local site, click "Book a Consultation."
2. Try submitting with a missing field, an invalid email, an invalid phone
   format, and a past date — confirm each shows a clear inline error and
   no request reaches the database.
3. Submit a valid booking — confirm a row appears in the `bookings` table
   with `payment_status = PENDING`.

### Testing payment (mock mode)
1. Set `PAYMENT_MODE=mock` in `.env` (never in a Production Vercel env).
2. Submit a booking — you'll land on `mock-checkout.html` instead of
   PayFast.
3. Click **Simulate Success** — confirm: the booking row updates to
   `payment_status = PAID`, `booking_status = CONFIRMED`; you land on
   `success.html` with correct details; both emails arrive (if
   `EMAIL_API_KEY` is set).
4. Repeat and click **Simulate Failure** — confirm the booking stays
   `FAILED`/not confirmed, you land on `failed.html`, and no emails are
   sent.
5. Reload the success/failed URL a second time — confirm the booking is
   **not** double-processed and no duplicate emails are sent (this proves
   idempotency).

### Testing real PayFast (once `initiateHostedCheckout` is implemented)
1. Set `PAYMENT_MODE=sandbox` and PayFast's sandbox credentials/base URL.
2. Repeat the same flow using PayFast's sandbox checkout and their
   documented test card/account numbers (get current sandbox test
   instruments from PayFast — don't guess these either).
3. Confirm `payfast-return.js` calls PayFast's real Get Transaction Status
   API and only marks `PAID` after a genuine `status_code: "00"` response.

---

## Sandbox → Production Checklist

1. Confirm real PayFast production `MERCHANT_ID` / `SECURED_KEY` are set in
   Vercel's **Production** environment only.
2. Set `PAYMENT_MODE=production` in the Production environment.
3. Run a real, small test transaction with a real card/account after go-live
   and confirm: booking marked PAID, both emails received, transaction
   visible in your PayFast merchant dashboard.
4. Only after that succeeds should you consider the system live.

**Do not** tell yourself (or anyone) the system is "fully working" until
this real end-to-end test has actually happened.

---

## Test Checklist

| # | Case | Expected |
|---|---|---|
| 1 | Valid booking | Booking created, `PENDING_PAYMENT` |
| 2 | Missing name | 400, field error, no DB row |
| 3 | Invalid email | 400, field error |
| 4 | Invalid phone | 400, field error |
| 5 | Past appointment date | 400, field error |
| 6 | Duplicate submission (double-click Pay) | Second request either creates a second distinct booking (acceptable) or is prevented client-side by disabling the button on submit (implemented) |
| 7 | Payment success | `PAID` / `CONFIRMED`, emails sent once |
| 8 | Payment failure | `FAILED`, no emails, no confirmation |
| 9 | Payment cancellation | Lands on `cancelled.html`, booking stays `PENDING`/unconfirmed |
| 10 | Invalid/forged payment callback | `getTransactionStatus` re-verifies against PayFast directly — a forged `?outcome=success` in the URL has no effect outside mock mode |
| 11 | Tampered amount from client | Ignored — `create-payment.js` always reads `amount` from the DB row, which has a `CHECK (amount = 1500)` constraint |
| 12 | Duplicate payment callback (replay) | `markPaymentResult` only updates a `PENDING` row; replays are no-ops that don't resend emails |
| 13 | Network failure calling PayFast | Caught, generic 502 to client, full error logged server-side |
| 14 | PayFast unavailable | Same as above |
| 15 | Email failure | Logged, does **not** fail the payment confirmation — booking still shows PAID/CONFIRMED |
| 16 | Database failure | Caught in each handler, generic 500 returned, no partial/inconsistent state exposed to the client |

---

## Security Checklist

This section was revised after a dedicated security review pass. Items
marked with a date were bugs found and fixed in that review, not
theoretical concerns.

- [x] PayFast secured key never appears in `public/`, frontend JS, or logs.
- [x] Price is defined once, server-side, in `api/create-booking.js`
      (`CONSULTATION_FEE = 1500`), enforced again by a DB `CHECK` constraint.
- [x] Client-supplied amount, if ever sent, is ignored.
- [x] Payment status is only ever set from a verified PayFast response
      (`getTransactionStatus`), never from a query parameter.
- [x] Payment processing is idempotent (`markPaymentResult` only transitions
      `PENDING` rows).
- [x] No card numbers, CVVs, PINs, or passwords are collected or stored.
- [x] Server-side input validation on every field (`lib/validate.js`),
      independent of client-side checks.
- [x] Security headers set in `vercel.json` (X-Frame-Options, nosniff,
      referrer policy, permissions policy, and now Content-Security-Policy).
- [x] `/api/*` responses set `Cache-Control: no-store`.
- [x] No sensitive data (card data, secrets, full request bodies) in
      `console.error` calls — only error messages and booking IDs.
- [x] **FIXED:** `api/create-payment.js` and `api/payfast-return.js` built
      redirect/return URLs from the client-supplied `Host` header when
      `SITE_URL` wasn't set — a spoofable header, which is a Host header
      injection / open-redirect risk. Both now use `lib/http.js`'s
      `getSiteUrl()`, which never trusts `Host` in production and requires
      `SITE_URL` to be set.
- [x] **FIXED:** the customer IP sent to PayFast for fraud scoring was taken
      from the *first* entry in `X-Forwarded-For`, which can be set by the
      client itself and doesn't reflect the real connecting IP on Vercel.
      `lib/http.js`'s `getClientIp()` now reads the *last* entry (appended by
      Vercel's own edge) and prefers `x-real-ip` when present.
- [x] **FIXED:** `appointmentTime` was only length-checked server-side, not
      format-checked — combined with `success.html` rendering booking
      details via `innerHTML`, a booking submitted directly to the API
      (bypassing the browser form) could have stored a script string that
      would execute in the browser of anyone who later viewed that booking's
      success page. Fixed on both ends: `lib/validate.js` now enforces a
      strict `HH:MM` format at submission time, and `success.html` was
      rewritten to build the DOM with `textContent` instead of `innerHTML`,
      so no stored value can ever be parsed as markup regardless of format.
- [x] **FIXED:** `api/booking-status.js` accepted any string as a booking ID
      with no format check and no rate limiting, making it an easy target for
      scripted enumeration. It now rejects anything not matching the real
      `SMK-YYYY-XXXXXX` shape before querying the database, and is
      rate-limited like the POST endpoints.
- [x] **FIXED:** rate limiting on `/api/create-booking`, `/api/create-payment`,
      and `/api/booking-status`, via `lib/rateLimit.js`. This uses Upstash
      Redis's REST API rather than an in-memory counter — Vercel serverless
      functions are stateless, so a plain in-memory counter would reset on
      nearly every request under real load and provide close to no actual
      protection. **This still needs `UPSTASH_REDIS_REST_URL` and
      `UPSTASH_REDIS_REST_TOKEN` set in Vercel before it does anything** — if
      unset, requests are allowed through and a warning is logged instead of
      silently pretending to be protected. Set these before taking the form
      fully public.
- [ ] **Known trade-off, not fixed:** the CSP in `vercel.json` includes
      `'unsafe-inline'` for `script-src`/`style-src`, because `index.html` (as
      originally built) relies on inline `<script>`/`<style>` blocks
      throughout. This still blocks loading scripts/styles from any
      *external* origin not on the allow-list, which is the more common
      injection vector, but it does not fully protect against inline script
      injection the way a nonce- or hash-based CSP would. Moving to nonces
      would require restructuring the inline blocks — a larger change than
      this review pass covered. Flagging it rather than quietly leaving it
      out of this list.
- [ ] **You still need to add:** a CAPTCHA (e.g. hCaptcha/Turnstile) on the
      booking form if spam becomes an issue in practice, in addition to the
      rate limiting above.
- [ ] **Recommended before real money flows through this:** an independent
      review by someone else, ideally with payments/security experience. I
      caught and fixed real bugs in my own first pass on this review — that's
      exactly why a second set of eyes matters here, not a reason to trust
      this list as final.

---

## Payment Testing Checklist

- [ ] Sandbox booking → sandbox PayFast checkout → success → booking PAID
- [ ] Sandbox booking → sandbox PayFast checkout → declined card → booking FAILED
- [ ] Sandbox booking → user closes/cancels checkout → lands on cancelled.html
- [ ] Reload the return URL after a completed payment → no duplicate emails
- [ ] Confirm PayFast sandbox dashboard shows the matching transaction
- [ ] One real, small production transaction before calling this "live"

---

## Ownership

You (the client) should own, directly:
- The PayFast merchant account and its settlement/bank account
- The domain
- The Vercel project/team
- The email account and Resend account
- The database (Vercel Postgres / Neon / Supabase account)

The developer should only need deploy access to the Vercel project and repo
access — never your bank, Easypaisa, or PayFast dashboard login/PIN/OTP.
