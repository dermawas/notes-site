---
layout: single
title: "Taming Decap CMS With AI — A Non-Coder’s Journey"
date: 2025-10-31 16:00 +0700
categories: ["notes"]
tags: ["flowformlab", "decap", "oauth", "ai-working-style", "vibe-coding"]
description: "How I built a working Decap CMS with GitHub OAuth despite not being a coder — and what building with AI really feels like."
---

I didn’t set out to become a developer.  
I wanted a simple personal lab — a place to document real projects, thinking, and learning in public.

I chose Jekyll, Minimal Mistakes, GitHub Pages… and Decap CMS, because writing in a text editor feels like climbing a mountain barefoot.

The domain setup was familiar territory.  
But GitHub? First time. Static sites? First time. OAuth? No thanks.

Still, step-by-step, with guidance, I created the repo, deployed the site, and saw it live.  
Then came the real adventure: enabling `/admin`.

---

### 💫 What I Wanted
Just one thing:

> *Click Login → write → publish.*

Easy in theory.  
In practice? Decap CMS + GitHub OAuth through Vercel is like a puzzle from an escape room designed by engineers who never expected normal humans to try this.

---

### ⚙️ The Loop
We wired OAuth. Token returned. Popup closed.

And the site said:

> **Login → Login → Login.**

An infinite loop of polite rejection.

The system said one thing, the browser another, and I had to insist on truth by checking real behavior.

---

### 🔍 The Real Fix
The key wasn’t code — it was **shape**:

Not a token alone, but a **full identity object** in browser storage:


Once that existed?  
Admin loaded. Login stable. Logout-login cycle reliable.

---

### 🧠 The Real Lesson

I didn't “code” this.  
I **steered** it.

I asked, verified, corrected hallucinations, insisted on *exact* files — no guessing.

Copy-paste programming isn’t cheating.  
It’s methodical building for non-coders:

1) Get it working  
2) Observe  
3) Understand gradually  
4) Own it

---

### 🚀 Why This Matters

AI isn't magic.  
It’s a thinking partner — one that needs grounding and clarity.

You don’t need to be a programmer to build on the web today.  
You need curiosity, persistence, and the courage to say:

> “No — show me exactly where that line goes.”

This site runs.  
The CMS works.  
And I built this not by coding,
but by *guiding the code into existence.*

FlowformLab continues.
