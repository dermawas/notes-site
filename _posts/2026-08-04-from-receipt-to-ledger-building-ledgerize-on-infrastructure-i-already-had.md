---
layout: single
title: "From Receipt to Ledger: Building a Mobile Expense Tracker on Infrastructure I Already Had"
date: "2026-08-04 20:00:00 +0700"
categories: ["notes"]
tags: ["mobile", "react-native", "postgresql", "self-hosted", "ai", "product-thinking"]
published: true
toc: true
toc_label: "Jump to section"
description: "Instead of trusting a third-party app with my real spending data, I built a receipt-scanning mobile app that syncs straight into the GnuCash ledger already running on my $0 OCI hub — no new server, no manual re-entry, no subscription. What worked, what broke on a real phone, and one small addition it forced back onto the infrastructure side."
author: "Archiles"
---

**TL;DR:** I built a React Native app that photographs a receipt, has AI split it into line items, and syncs each one straight into the same GnuCash ledger [running on the OCI hub from the last post](/notes/2026/06/01/the-accidental-platform-how-one-free-server-grew-into-a-private-infrastructure-hub/) — no manual re-entry, no new server. Built mostly with Claude Code. The interesting bugs only showed up once it was on a real phone, and one of them sent me back to add a small safety-net script to the infrastructure side.

---

## The gap the last post left open

In [The Accidental Platform](/notes/2026/06/01/the-accidental-platform-how-one-free-server-grew-into-a-private-infrastructure-hub/) I described GnuCash + PostgreSQL running on the same free OCI VM as everything else — reachable from any device on the VPN, no Dropbox device limit, no subscription.

That solved *storage*. It didn't solve *entry*.

Every consumer expense tracker I looked at wanted one of two things: trust it with my real spending data and hope it stays private, or use it as a scratchpad and manually re-type everything into GnuCash later anyway. Neither was worth it. The ledger already existed and already worked. What was missing was a fast, low-friction way to get a receipt *into* it — correctly categorized, without typing anything twice.

## What I built

A React Native (Expo) app — working name **Ledgerize** — with two ways to use it:

- **Standalone** — a normal mobile expense tracker on its own backend (Supabase), for anyone who just wants item-level categorization without touching GnuCash at all.
- **GnuCash Sync** — the mode I actually use. Same app, same account, but every transaction also gets written into the real ledger on the OCI hub.

The part I actually wanted was receipt scanning that doesn't stop at "total: Rp 87,400." A single trip to the grocery store might be a dozen line items across four or five categories. An AI vision call reads the receipt, splits it into items, and proposes a category per line — a 20-item receipt becomes 20 correctly-categorized ledger entries in about the time it takes to type one.

## No client ever holds a real API key

The AI call itself is backend-proxied — the phone never holds a provider key, root or not. It hits a small server-side function that holds the real key, calls the model, and returns structured results. Quota is enforced server-side too, never trusted from the client. Same reasoning as keeping WireGuard keys off anything that isn't the tunnel endpoint itself: a secret the app has to decrypt and use at runtime isn't actually secret.

## The GnuCash Sync layer — not a shortcut through the database

The tempting shortcut would have been to point the phone straight at the PostgreSQL instance from the last post. I didn't do that, for the same reason I didn't reuse `keepass.vpn`'s Apache instance to also serve a raw database port to a mobile app: a phone app is a much bigger attack surface than a desktop client on a trusted network, and "the app can read/write the same tables GnuCash desktop uses" is a much bigger blast radius than I wanted.

Instead: a small self-hosted [PostgREST](https://postgrest.org/) layer sits between the phone and Postgres. The phone holds a JWT naming a Postgres role; PostgREST switches into that role per request, then back. That role can't touch `transactions` or `splits` directly at all — it only gets `EXECUTE` on two `SECURITY DEFINER` functions:

- `sync_transaction(...)` — writes a balanced double-entry transaction (every write sums to exactly zero, the same invariant GnuCash itself enforces), checks an idempotency marker first so a retried request can't double-post, and reads the account's own currency fraction instead of assuming everything is whole units.
- `check_transaction_drift(...)` — read-only, lets the app notice if something it synced was later edited directly in GnuCash desktop.

A bug in the app or a leaked JWT can't alter schema or touch anything outside those two functions. The actual owner of the ledger is still GnuCash desktop, connecting the normal way. The phone is a narrow-scope guest.

## AI did the fast part; a real phone found the real bugs

Claude Code wrote nearly all of this — the app, the sync functions, the review screens. It's genuinely fast at that. But the same lesson from the L2TP mistake in the last post held here too: confidence isn't correctness, and the interesting failures only showed up once real data hit a real device.

Two examples, because they were the kind of bug that a demo would never surface:

- **A sign-out race.** Switching accounts on the same phone could, for a brief window, show the *previous* account's real wallets and categories under the new session. Store state was cleared, but a handful of screens had their own `useEffect` that refetched on any auth change — including the transition to signed-out — with the old token still technically valid until revocation finished. Never showed up in a quick test; showed up immediately once I was actually switching between two real accounts on one phone.
- **A currency-mismatch that was silently wrong, not silently absent.** Mapping an IDR wallet to a GnuCash account whose real commodity was USD didn't error — GnuCash auto-balanced the cross-currency transaction via its own trading accounts, and the ledger just quietly recorded 15,000× too much. No exception anywhere to catch in testing; only a discrepancy you'd notice by actually reading your own numbers.

Neither would have been caught by anything short of using the thing for real, on a real device, against a real ledger.

## The near-miss that sent me back to the infrastructure side

The most interesting one: the AI occasionally misreads a printed date on a receipt — in one case, off by exactly two years. Caught it during testing, but it made an uncomfortable point: a receipt-scanning app has a direct, automated write path into a real accounting ledger, and a plausible-looking date is exactly the kind of error nothing downstream would ever flag on its own.

Rather than trust that it'll always get caught by a human mid-test, I added one more script to the OCI hub: a weekly job that scans recent GnuCash entries for an unusually large gap between when something was recorded and the date it claims, and reports the result to the same Telegram bot from the last post — plus an on-demand `/GnuCashDateCheck` command so I can ask it to check right now instead of waiting for Monday. Same "Telegram as monitoring plane" pattern as the router alerts and the WireGuard peer watcher; just one more consumer of infrastructure that already existed.

That's the shape this project kept taking: every time the mobile app needed a new capability, the answer was usually "extend what's already running," not "stand up something new."

## Reuse over buy, continued

| Need | Instead of... | I used |
|---|---|---|
| AI receipt reading | Client-side API key, or a paid document-scanning SaaS | One backend function proxying a single provider key, quota enforced server-side |
| Sync transport | Exposing Postgres directly to a mobile app | Self-hosted PostgREST + JWT role impersonation, on the same $0 OCI VM |
| Date-integrity monitoring | Trusting manual QA to always catch it | One more script on the existing Telegram-bot pattern |
| Distribution | $25 Play Store listing before knowing anyone wants it | Direct APK download via GitHub Releases |
| Alerting | A dashboard I'd have to remember to check | The same Telegram group everything else already reports to |

Nothing here is exotic. It's the same discipline as the last post: before adding a new piece, ask whether something already running can be extended instead.

## What runs today

| Layer | Technology |
|---|---|
| Mobile app | React Native (Expo), file-based routing |
| Standalone backend | Supabase (Postgres, auth) |
| AI receipt scanning | Server-proxied vision model call, no client-held keys |
| GnuCash Sync transport | Self-hosted PostgREST on the OCI hub |
| Ledger | The same GnuCash + PostgreSQL from [the last post](/notes/2026/06/01/the-accidental-platform-how-one-free-server-grew-into-a-private-infrastructure-hub/) |
| Date-integrity check | Weekly cron + on-demand Telegram command, same bot as everything else |
| Distribution | Direct APK via GitHub Releases (Play Store: not yet) |

## Try it

It's a market-test beta, not on Google Play yet — direct APK install, GnuCash Sync is optional and off by default. If you already run GnuCash and want to see whether AI-assisted item-level receipt scanning is actually worth the setup:

**[Ledgerize →](https://forstradigital.com/ledgerize.html)**

---

*The infrastructure this syncs into:* [The Accidental Platform: How One Free Server Grew Into a Private Infrastructure Hub →](/notes/2026/06/01/the-accidental-platform-how-one-free-server-grew-into-a-private-infrastructure-hub/)
