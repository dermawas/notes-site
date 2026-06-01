---
layout: single
title: "When ChatGPT Cost Me Two Weeks and a Holiday in Traffic"
date: "2026-04-07 10:00:00 +0700"
categories: ["notes"]
tags: ["ai", "chatgpt", "lessons-learned", "networking", "mikrotik", "l2tp"]
published: true
toc: true
toc_label: "Jump to section"
description: "I was a paying ChatGPT subscriber. It gave me confident, detailed, wrong architectural advice. I followed it anyway. Here is the full story — and how I work with AI differently now."
author: "Archiles"
---

**TL;DR:** ChatGPT gave me confidently wrong architectural advice about L2TP networking. I doubted it. It insisted. I gave in. That cost me two weeks and multiple drives through Lebaran holiday traffic. This is the full account — and what I changed afterward.

---

## Background

I have been building a private infrastructure hub on an OCI Always Free VM — WireGuard, L2TP/IPSec, self-hosted password vault, accounting, DNS, monitoring. The full story of how that came together is in a separate piece written later, once the build was complete: [The Accidental Platform →](/notes/2026/06/01/the-accidental-platform-how-one-free-server-grew-into-a-private-infrastructure-hub/)

This article is about one specific chapter of that journey — the one that went wrong. I'm writing it while it's still fresh.

---

## The problem I was trying to solve

I have two sites — Site A (main) and Site B (remote) — each with a MikroTik router. I needed to:

- Remotely manage the Site B router via WinBox from Site A
- Access a 4G modem at Site B to retrieve SMS messages

A site-to-site VPN was the obvious answer. I was physically at Site B when I started working on it. I asked ChatGPT — I was a paying subscriber at the time — for help.

---

## The wrong advice, and why I trusted it

ChatGPT's suggestion: configure a direct L2TP/IPSec tunnel between the two MikroTik routers. Site A as server, Site B as client.

The catch: it told me to configure the client at Site B first, then set up the server when I returned to Site A.

I paused. I understood the protocol. I asked:

> "Site B doesn't know what IP address the Site A server will have. How can we configure the client first?"

ChatGPT insisted it was possible. It suggested dynamic DNS. It asked me to provide the local IP of Site A.

I knew that local IP was not publicly reachable. A client cannot find a server that sits behind NAT with no public endpoint. This was basic networking. I knew it was wrong.

But the AI sounded completely confident. It had helped me successfully with WireGuard setup, Telegram scripting, and bash automation. I had built up trust in it. Against my better judgment, I gave in.

I provided the local IP. I configured the Site B client. I noted that there was no way to test the connection before leaving — ChatGPT confirmed this, calling it unavoidable given the direct-tunnel design. That should have been a second red flag.

---

## The cost

I returned to Site A. With ChatGPT's help, I configured the server side.

No connection. Site B did not connect.

ChatGPT did not say "the architecture was wrong." It offered new configurations to try. Firewall rules. MTU adjustments. Routing tweaks. Each one confident. Each one wrong.

Here is what the next two weeks looked like:

| Trip | Driving time |
|---|---|
| Site B → Site A (initial return) | 2 hours |
| Site A → Site B (first troubleshooting attempt) | 4–8 hours (Lebaran holiday traffic) |
| Site B → Site A → Site B (day trip) | 8–16 hours round trip |
| Site B → Site A (final return) | 2+ hours |

The route between the two sites passes through Puncak — one of the most congested holiday routes in Indonesia. During Lebaran, the busiest holiday of the year, what is normally a 2-hour drive becomes 4 to 8 hours one way.

One additional factor that ChatGPT had completely missed: the ISP at Site B blocks certain direct inbound connection types at the network level. No configuration change on either router would have fixed that. The architecture was wrong from the start.

---

## The breakthrough: asking the right question

After the second failed trip, I stopped asking "How do I fix this configuration?" and started asking "Is this even the right architecture?"

It wasn't.

I already had a working WireGuard hub on OCI — static public IP, proven routing, always on. Both sites could already reach it. The obvious design had been in front of me the whole time:

- Both sites connect as L2TP clients to OCI
- OCI acts as the central server
- OCI routes between them

```
Site A ──L2TP──► OCI ◄──L2TP── Site B
                  │
             WireGuard
                  │
           Remote devices
```

With ChatGPT's help — this time on a design I had chosen myself — I configured the OCI side and both routers. It connected. The difference wasn't the AI. It was the architecture.

---

## The second mistake — and the fix that saved me another trip

With the new architecture working, I had a new concern: I was still at Site B. Once I left, I wouldn't be back for months. I needed to verify the connection was truly working before I left.

I asked ChatGPT: "Can I test from my Android phone — which is connected to OCI via WireGuard — whether I can WinBox into the Site B router over this L2TP tunnel?"

ChatGPT said no. Too complex. Would require routing changes it described as impractical.

I didn't accept that. I pushed back. I asked specifically for:

- Routing rules to connect the WireGuard network (`10.8.0.x`) to the L2TP network (`10.50.0.x`) on OCI
- Correct firewall rules on the Site B MikroTik to allow the connection
- The right PPP interface bindings and IP pool configuration

ChatGPT resisted, then gave partial answers, then eventually gave the correct configuration when I kept pushing with specific technical questions.

From my Android phone, over WireGuard → OCI → L2TP → Site B, I opened WinBox. The connection worked.

That test — which ChatGPT twice said was impossible — saved me another round trip.

I asked ChatGPT to document the working configuration so I could replicate it at Site A when I returned. That part it did well.

---

## What this taught me about AI

I still use AI tools every day. I use ChatGPT (free tier now), Claude, and DeepSeek. I cross-check important answers across models.

But the way I use them changed.

### Before

- Treated confident answers as validated answers
- Followed AI-generated architecture without questioning the design
- Assumed that detailed, plausible instructions meant the approach was correct
- Proceeded without testable checkpoints

### After

| Old habit | New habit |
|---|---|
| "How do I do X?" | "What is the simplest reliable way to solve this problem?" |
| Trust confidence | The more confident the answer, the more I verify it |
| Follow instructions | Demand a testable outcome before committing time or travel |
| One AI | Cross-check with multiple models |
| AI as architect | AI as implementation help — architecture is mine |

The most useful question I added to my workflow:

> "How will I know this works before I leave this location?"

If the answer is "you can't test it until later" — that is a design problem, not a constraint to accept.

### On naming ChatGPT specifically

I want to be precise here. ChatGPT was not bad. For much of this project — WireGuard setup, Telegram bot scripting, bash automation, documentation — it was genuinely useful. The article I wrote about building the Telegram-MikroTik workflow exists because of it: [The AI Architect: Wrestling ChatGPT into Building a Robust Telegram-to-MikroTik Workflow →](/notes/2025/11/21/the-ai-architect-wrestling-chatgpt-into-building-a-robust-telegram-to-mikrotik-workflow/)

What failed was a specific architectural judgment call — one that required understanding CGNAT, public IP reachability, and how ISPs handle inbound connections. That is context-dependent, real-world knowledge that AI cannot reliably verify from within a conversation.

The mistake was mine: I trusted a confident answer on an architectural question when I already had doubts. A paid subscription does not buy correctness. It buys speed. Speed without verification is just a faster way to be wrong.

---

## The rule I actually use now

When working with AI on anything that involves real-world infrastructure, real travel, or real consequences:

**1. Design the architecture yourself first.**
Describe the problem. Ask the AI what approaches exist. Then decide which one. Don't let the AI pick the architecture.

**2. Before implementing, ask: how do I test this without going anywhere?**
If you can't test it from your phone over an existing VPN, the design has a dependency you haven't solved yet.

**3. When the AI sounds most confident, verify most carefully.**
Confidence and correctness are not correlated in AI outputs. The detailed, specific, authoritative-sounding answers are often the ones worth questioning most.

**4. Cross-check anything architectural with a second model.**
Claude, DeepSeek, and ChatGPT often disagree on networking questions. That disagreement is useful information.

**5. When the AI says something is impossible — push back once.**
Not to be difficult. But because "too complex" is sometimes a lazy answer. I asked twice. Twice it gave me what I needed.

---

## Final thought

The disclaimer every AI platform shows — *AI can make mistakes. Verify important information* — is not legal boilerplate.

I read it many times. I moved on. I trusted the tool.

This project turned that warning into a practical lesson I won't forget.

I still talk to AI every day. But now I talk to it the way I would talk to a clever colleague who is extremely well-read but has never physically set up a network:

> "That is an interesting suggestion. Now show me how I can test it before I commit."

That one question would have saved me two weeks and a holiday in traffic.

---

*This article is part of the OCI infrastructure series:*
- *[The Accidental Platform →](/notes/2026/06/01/the-accidental-platform-how-one-free-server-grew-into-a-private-infrastructure-hub/)* — the full infrastructure build, written after everything was complete
- *[The AI Architect: Wrestling ChatGPT into Building a Robust Telegram-to-MikroTik Workflow →](/notes/2025/11/21/the-ai-architect-wrestling-chatgpt-into-building-a-robust-telegram-to-mikrotik-workflow/)* — building the Telegram control system
