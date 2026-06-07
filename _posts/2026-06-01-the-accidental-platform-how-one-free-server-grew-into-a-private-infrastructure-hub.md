---
layout: single
title: "The Accidental Platform: How One Free Server Grew Into a Private Infrastructure Hub"
date: "2026-06-01 10:00:00 +0700"
categories: ["notes"]
tags: ["oci", "wireguard", "infrastructure", "product-thinking", "self-hosted"]
published: true
toc: true
toc_label: "Jump to section"
description: "What started as a single WireGuard tunnel for China travel grew into a zero-cost private infrastructure hub running passwords, accounting, DNS, monitoring, and site-to-site networking. The story of building through reuse, not purchase."
author: "Archiles"
---

**TL;DR:** I built a private infrastructure hub on an OCI Always Free VM — not by planning it, but by repeatedly asking "can I solve this with what I already have?" WireGuard came first. Everything else followed. Cost: $0.

---

## It started with China

I needed Gmail in China. My paid VPN was unreliable and another recurring subscription I didn't want.

So I built my own. Oracle Cloud Always Free VM. WireGuard. Phone and laptop as peers. One tunnel, one purpose. It worked.

The VM sat mostly idle after that. So when the next problem came up, I didn't go looking for a new SaaS product. I asked: *Can I solve this with what I already have?*

That question changed everything.

Today that same VM runs:

- WireGuard (remote access from anywhere)
- L2TP/IPSec connecting Site A and Site B
- KeePass + WebDAV (password vault, no device limits)
- GnuCash + PostgreSQL (accounting from anywhere)
- AdGuard Home (internal DNS — `keepass.vpn` instead of an IP)
- Telegram bots (monitoring, alerts, remote control)
- Automated backups to Dropbox and GitHub

CPU load ~1%. Cost: $0 per month.

This is the story of how that happened — and the one expensive mistake that taught me the difference between executing a plan and owning the outcome.

---

## The architecture, in one diagram

```
                        Internet
                            │
                    OCI VM (public IP)
                    ┌───────┴────────┐
                    │                │
               WireGuard          L2TP/IPSec
              (wg0 10.8.0.x)    (10.50.0.x)
                    │           ┌────┴────┐
              Remote devices  Site A   Site B
              (phone, laptop)
                    │
          ┌─────────┼──────────┐
     keepass.vpn  gnucash.vpn  document.vpn
     (WebDAV)    (PostgreSQL)  (Apache)
```

> 📄 **Full Technical Reference** — topology diagram, service stack, security design, and more:
> [OCI VPN Hub — Technical Reference →](/oci-vpn-hub-public.html)

All three populations — remote WireGuard peers, Site A LAN, Site B LAN — reach the same services using the same DNS names. No split DNS. No per-device configuration.

---

## Feature by feature: reusing what I had

I never planned any of this. Each piece came from a real annoyance.

### WireGuard — the seed

**Problem:** Free VPN for China travel. I don't want to pay for one.

**Solution:** OCI VM + WireGuard. Done in an afternoon.

That was it. One tunnel, one purpose. But now I had a VM with a static public IP that I trusted. That matters for everything that came after.

### L2TP/IPSec — the hard lesson

**Problem:** Two physical sites (Site A and Site B), each with a MikroTik router. I needed to remotely access the Site B router and its 4G modem — to manage settings and retrieve SMS messages — all from Site A.

A site-to-site VPN was the obvious answer. What wasn't obvious was the architecture.

I made an expensive mistake here: I followed AI-generated instructions for a direct Site A ↔ Site B tunnel, ignoring my own doubts about whether it could work. It didn't. Two weeks and multiple long drives later, I redesigned it myself.

The right answer was in front of me the whole time: reuse the OCI VM as a central L2TP hub. Both sites connect to OCI. OCI routes between them.

**Capability reused:** The same VM that ran WireGuard now also runs L2TP. No second server. No extra cost.

I wrote the full story of that mistake — and what it taught me about working with AI — in a companion piece: [When ChatGPT Cost Me Two Weeks and a Holiday in Traffic →](/notes/2026/04/07/when-ai-costs-you-more-than-time/)

### KeePass + WebDAV — Dropbox hit its limit

**Problem:** Dropbox free tier limits sync to 3 devices. I have more than 3 devices. My KeePass vault needed to follow me everywhere.

**Solution:** WebDAV server on the OCI VM. Apache, HTTPS, Digest auth. KeePass points to `https://keepass.vpn`. Done.

No device limit. No third party with access to my vault.

**Capability reused:** Same VM. Same Apache instance that was already installed.

### GnuCash + PostgreSQL — same Dropbox problem

**Problem:** Same 3-device limit, this time for GnuCash accounting files.

**Solution:** PostgreSQL on OCI. Any device on the VPN connects to `gnucash.vpn:5432`. The database is always there, always current.

**Capability reused:** Same VM. PostgreSQL added alongside everything else.

### AdGuard Home — I'm lazy with IPs

**Problem:** Remembering IP addresses for different services is annoying and error-prone.

**Solution:** AdGuard Home on OCI. It resolves `keepass.vpn`, `gnucash.vpn`, and `document.vpn` for every device connected via WireGuard or via either site's local network (when the L2TP tunnel is up). One namespace everywhere.

**Capability reused:** Same VM, now also a DNS server.

### Telegram bots — I need to know when things break

**Problem:** How do I know if Site B loses connectivity or a service goes down?

**Solution:** Each MikroTik router sends a status message (CPU, RAM, uptime) to a Telegram group every ten minutes. If a message goes missing, I investigate. I extended this to monitor WireGuard peers, bandwidth thresholds, KeePass access events, and GnuCash database activity. I can also toggle the L2TP tunnels on or off from Telegram.

**Capability reused:** Telegram — something I was already using — became the monitoring and control plane. No paid uptime service. No new dashboard.

The full story of building that Telegram bot is here: [The AI Architect: Wrestling ChatGPT into Building a Robust Telegram-to-MikroTik Workflow →](/notes/2025/11/21/the-ai-architect-wrestling-chatgpt-into-building-a-robust-telegram-to-mikrotik-workflow/)

---

A note on tooling: most of this was built with AI assistance — primarily ChatGPT early on, and increasingly Claude as the project matured. The free tier limits on both make development slower than it needs to be, but the cost-to-output ratio is still remarkable. More on that in the companion piece.

## The pattern: reuse over buy

Looking back, the same thing happened every time:

| New problem | Instead of buying... | I reused |
|---|---|---|
| China VPN | Paid VPN subscription | OCI + WireGuard |
| Site-to-site access | Cloud SD-WAN or a second VPS | OCI as L2TP hub |
| Password sync | Cloud password manager | OCI + WebDAV |
| Accounting sync | Cloud accounting service | OCI + PostgreSQL |
| DNS names | Public DNS or hosts files | OCI + AdGuard |
| Monitoring | Paid uptime service | Telegram + bash |

This is not a grand architecture. It is just refusing to add a new tool every time something annoys me.

The question that drove every decision: *Can I solve this with what I already have?*

---

## Project thinking vs product thinking — both matter

A project manager asks: *Can I execute this plan correctly?* That is valuable. It keeps things moving, on scope, on time.

But that question assumes someone already asked the harder one: *Is this the right plan?*

That second question is product thinking. It is not better than project thinking — it is a different layer on top of it. You need both.

The only time this whole build went wrong was when I forgot to ask the second question. I was so focused on executing the AI's instructions for the direct site-to-site tunnel that I never stopped to ask whether those instructions were pointing me toward the right solution.

They weren't.

Once I stepped back and asked *Is this even the right architecture?* the answer was obvious. And the fix took about an hour.

Wearing both hats — execute well, but also stop and ask whether you're executing the right thing — would have saved me two weeks and a holiday in traffic.

---

## What runs today

| Component | Technology | Cost |
|---|---|---|
| Remote VPN | WireGuard | $0 |
| Site-to-site | L2TP/IPSec (OCI as hub) | $0 |
| Password vault | KeePass + Apache WebDAV | $0 |
| Accounting | GnuCash + PostgreSQL | $0 |
| DNS + ad-block | AdGuard Home | $0 |
| Monitoring & control | Telegram bots (custom bash) | $0 |
| Backups | rclone + Dropbox + GitHub | $0 |

All on one OCI Always Free VM. 1 GB RAM, 2 vCPUs, 45 GB storage. Typical CPU: ~1%.

---

## Final thought

I didn't plan any of this. I just kept solving the next annoying problem with what I already had.

That mindset — reuse over buy, extend over add — is worth more than any single piece of technology in this stack.

The only time I forgot it, I lost two weeks and a holiday in traffic.

Now I don't forget.

---

*The AI lesson in full:* [When ChatGPT Cost Me Two Weeks and a Holiday in Traffic →](/notes/2026/04/07/when-ai-costs-you-more-than-time/)

*The Telegram bot build:* [The AI Architect: Wrestling ChatGPT into Building a Robust Telegram-to-MikroTik Workflow →](/notes/2025/11/21/the-ai-architect-wrestling-chatgpt-into-building-a-robust-telegram-to-mikrotik-workflow/)
