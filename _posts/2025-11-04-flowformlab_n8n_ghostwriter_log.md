---
layout: single
title: "FlowformLab AI Ghostwriter — Build Log"
description: "Day-by-day build log creating an n8n + Ollama automation to generate blog posts and integrate with Decap CMS."
date: 2025-11-04
categories: [automation, ai, notebook]
tags: [n8n, ollama, decap cms, jekyll, flowformlab, automation log]
toc: true
toc_label: "Jump to section"
toc_icon: "cog"
author: "Suseno Dermawan"
published: true
---

# Project Log: n8n Ghost Writer Automation with Local LLM (Ollama)

## Summary

This entry documents the initial build and iterative refinement of the
**Ghost Writer automation pipeline** for FlowformLab --- a local,
privacy-preserving content generation workflow powered by **n8n** and
**Ollama**.\
The objective is to accelerate first-draft creation while preserving
personal narrative, structure, and editorial control.

The pipeline now accepts a topic, generates structured headings, TL;DR
and diagrams, writes the article body, and merges outputs into
FlowformLab-ready Markdown.

## Work Timeline

| Date | Milestone | Key Activities | Output |
|------|-----------|----------------|--------|
| **Sat, 1 Nov 2025** | Kickoff | Defined goals & writing constraints. Set up n8n / Ollama baseline. | Project charter + architecture outline |
| **Sun, 2 Nov 2025** | Headings Engine | Built 3-heading generator sub-workflow, JSON parser + fallbacks | Stable headings module |
| **Mon, 3 Nov 2025** | TL;DR + Diagram Engine | Added TL;DR + Mermaid diagram subflow w/ resilience to parsing errors | Summary + diagram generator |
| **Tue, 4 Nov 2025** | Body Writer + Merge | Built body writer, added Markdown cleanup + JSON recovery, final merge logic | ✅ End-to-end pipeline working |

> **Total time invested:** ~4 days (iterative)  
> **Milestone achieved:** Fully automated topic → structured draft flow


## Deliverables Completed

-   ✅ Topic input node\
-   ✅ 3-heading generator + JSON normalization\
-   ✅ Auto-pick + manual override capability\
-   ✅ TL;DR + Mermaid diagram generator\
-   ✅ Body writer workflow\
-   ✅ Markdown assembler with safety checks\
-   ✅ Output: FlowformLab-ready draft (`article_md`)

## Architecture Overview

    [ Input ] 
       ↓
    [ Headings Subflow ]
       ↓ pick
    [ TL;DR + Diagram Subflow ]
       ↓
    [ Body Writer Subflow ]
       ↓
    [ Merge & Clean ]
       ↓
    [ Draft Markdown Output ]

## Risks & Mitigation

  ------------------------------------------------------------------------------
  Risk              Description    Likelihood     Impact         Mitigation
  ----------------- -------------- -------------- -------------- ---------------
  Model drift       LLM breaking   Medium         Medium         Strong prompt
                    JSON rules                                   guardrails,
                                                                 fallback
                                                                 defaults,
                                                                 post-parsers

  Pipeline          Parsing or     Medium         High           Unified
  fragility         mapping breaks                               normalizer
                                                                 functions +
                                                                 stricter schema

  Stylistic         Output doesn't Medium         Medium         Style
  inconsistency     match                                        constraints +
                    FlowformLab                                  post-edit
                    tone                                         process

  Over-automation   Losing         Low            High           Human-edit
                    personal voice                               stage always
                                                                 required

  Future version    Ollama updates Low            Medium         Version
  changes           break behavior                               pinning +
                                                                 regression test
                                                                 prompts
  ------------------------------------------------------------------------------

## Next Steps (Backlog)

  -----------------------------------------------------------------------
  Priority                Task                    Notes
  ----------------------- ----------------------- -----------------------
  High                    Connect to Decap CMS to Commit to `/_drafts/`
                          push draft files        

  High                    Style selector input    Adds brand personality
                          (Reflective / Technical 
                          / Audit PMO)            

  Medium                  Template system for     Needed for FlowformLab
                          YAML front-matter + MM  posts
                          layout                  

  Medium                  Mermaid diagram         Clean layout + label
                          refinement layer        rules

  Low                     Long-form structuring   For deep essays
                          (sections, ToC)         
  -----------------------------------------------------------------------

## Reflection

This pipeline now acts as a **personal strategic writing co-pilot**, not
a content spawner. FlowformLab remains human-led --- this tool just
accelerates clarity.

------------------------------------------------------------------------
