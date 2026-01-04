---
title: "2026: Working With AI, Not Letting AI Work For Me"
date: 2026-01-04 12:17:00 +07:00
categories:
  - notes
description: '"A year-end reflection on working with AI in real-world networking
  and automation projects, and what I learned the hard way."'
toc: false
published: true
advanced:
  layout: single
  author_profile: false
---

## Happy New Year 2026


I hope this year will be a better, calmer, and more humane year for everyone — especially for those of us who spend most of our days building, fixing, and learning digital systems that are never quite finished.

As the year turns, I want to document one important chapter from my personal lab: **my experience working with AI on real infrastructure projects**.  
Not demos. Not toy problems. But systems that actually run at home and in the cloud.

This might also be my **last major “experiment” phase with AI**, at least in its current form.

---

## Project A — MikroTik RouterOS 6 + Telegram Automation

### What I Built

A MikroTik RouterOS **v6** automation setup where:

- Telegram commands are received by the router  
- Commands trigger RouterOS scripts  
- The router sends structured responses back to Telegram  
- Telegram credentials are centralized using global variables  

In short: **human → Telegram → MikroTik → Telegram**, reliably.

### Advantages

- AI can produce scripts **very quickly**
- Debugging can be efficient *when the AI is focused*
- Pattern recognition (polling, parsing, messaging) is genuinely helpful

### Disadvantages

- The AI frequently **forgets RouterOS v6 syntax** and defaults to RouterOS v7
- It often **forgets or breaks the logical flow that I explicitly designed**, for example:

  A. Create or maintain a file to store the Telegram update ID  
  B. Fetch only new Telegram messages  
  C. Update the cursor with the latest processed update ID  
  D. Call a separate script to send a confirmation message  

  Even though this flow is valid, tested, and required for reliable operation, the AI often reorders, omits, or partially rewrites these steps in ways that **do not work in RouterOS 6 scripting reality**.

- Each new conversation often resets context
- Days — sometimes weeks — are spent re-explaining:
  - Script execution constraints
  - File handling behavior
  - Telegram formatting limits
  - RouterOS parser quirks

### Outcome

Despite the friction, the outcome is solid:

- Telegram commands reliably control MikroTik behavior
- Telegram messaging is cleaner and more consistent
- Credentials are stored centrally instead of duplicated
- The router becomes a controlled, observable system

This worked — but only because I stayed skeptical and hands-on.

---

## Project B — Site-to-Site VPN via Oracle Cloud Infrastructure

### What I Built

- Two MikroTik routers at different physical sites  
- One site using **4G with dynamic IP**  
- Oracle Cloud Infrastructure (OCI) as a **central VPN hub**  
- Combination of **WireGuard + L2TP/IPsec**  
- Routed access to local resources (no internet sharing)

### Advantages

- AI is very strong with **Linux systems**
  - WireGuard
  - L2TP services
  - Firewall rules
  - Routing tables
- Linux networking is easier to reason about
- RouterOS configuration is usually correct *in theory*

### Disadvantages

- MikroTik commands again default to RouterOS v7
- AI often misses **real-world constraints**, such as:
  - 4G connections not supporting direct inbound L2TP
- The correct architecture (OCI as hub) had to be guided by me
- AI can be overly confident without testing
- Real validation required:
  - Moving between sites
  - Using WireGuard clients as test probes
  - Verifying one site fully before replicating the setup

### Outcome

Eventually, success:

- Two MikroTik routers connected through OCI
- Local resources accessible across sites
- No internet sharing (by design)
- A clean and understandable routing model

Again, this worked — because I did not trust the AI blindly.

---

## What AI Really Is (For Me)

This experiment confirmed something important:

> **AI is a great research and acceleration tool — not a substitute for understanding.**

Building serious digital systems alone is now possible, **as long as**:

1. You know the outcome you want and can challenge wrong answers  
2. The language or platform has enough public knowledge  
3. You remain skeptical when AI is very confident  

Confidence does not equal correctness.

---

## What’s Next in 2026

Ironically, the lesson is not to stop using AI.

In 2026, I plan to:

- Work closer with AI  
- Learn broader and deeper technical domains  
- Improve my ability to detect bluffing  
- Stay hands-on with systems that actually break when done wrong  

The more you know, the harder it is for AI to fool you —  
and the more powerful the collaboration becomes.

---

*This reflection is part of my ongoing learning journal at FlowformLab — a place where experiments are documented honestly, including the parts that didn’t go smoothly.*
