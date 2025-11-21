---
title: "The AI Architect: Wrestling ChatGPT into Building a Robust
  Telegram-to-Mikrotik Workflow"
date: 2025-11-21 12:24:00 +07:00
categories:
  - notes
excerpt: Discover how to build a Telegram based remote command system for your
  Mikrotik router with ChatGPT. This guide shares critical lessons on guiding AI
  to avoid common pitfalls and achieve robust automation.
description: Automate your Mikrotik with Telegram commands! See how we used
  ChatGPT to build a reliable remote control script, overcoming syntax errors
  and ensuring commands run only once. Essential lessons for AI powered network
  automation.
toc: false
published: true
advanced:
  layout: single
  author_profile: false
---



In the world of network automation, the ability to trigger router scripts remotely via a simple chat message is a massive convenience. The goal was straightforward: I wanted to send a command to a private Telegram group (like `!block deviceX`) and have my Mikrotik router pick it up and execute the corresponding script.

I had the components: a Mikrotik router, a Telegram bot setup via BotFather, and ChatGPT to handle the scripting glue between them.

What followed was a two day crash course not just in Mikrotik scripting syntax, but in the practical realities of acting as a systems architect when your junior developer is an AI. Here is the workflow of how we went from a broken monolithic script to a robust, modular system.



### Phase 1: The Monolithic Failure (Day 1)



My initial approach was casual. I provided ChatGPT with a general prompt asking for code that would allow the Mikrotik to read a Telegram message and run a command based on it.

ChatGPT obliged, suggesting a single, long script utilizing a syntax like `!<pin><ScriptName>`. We spent half a day debugging this monolithic block of code. Finally, it worked. The router received the command and executed the script.

The "Idempotency" Problem

Victory was short lived. We immediately realized a critical flaw in the logic: there was no mechanism to track which commands had already been run. If the router checked Telegram again, it would see the same message and re run the script.

When I asked ChatGPT to modify the script to track message IDs and ensure a command only runs once, the house of cards collapsed. The AI’s attempt to integrate this new logic into the existing massive script broke the entire flow. The code became unusable.

Lesson Learned: Vague prompts yield fragile, monolithic code. Complex logic requires structured requests.



### Phase 2: Strategic Prompting and Modularization (Day 2)



Realizing that a casual approach wouldn't work for complex state management, I started a fresh conversation with a highly specific prompt. I defined the existing environment, the exact desired outcome, and crucial constraints.

> The Pivot Prompt:
> "I already have a script to block/unblock devices. I already have the Mikrotik able to send messages to telegram... now I want to run this script from Telegram group.
>
> Note of caution: if I send a message in telegram to run a script, it should only run once, unless I send another message. What information do you need from me... to read a trigger message and run the script?"

ChatGPT requested necessary details (API tokens, chat IDs) and provided a new single script. Once again, we hit a wall of Mikrotik syntax errors that were nearly impossible to debug within a single large file.

Taking the Reins: The Modular Shift

This was the turning point. I realized I couldn't just ask the AI to "build the whole thing." I needed to act as the Lead Architect and force the AI to build testable components. I instructed ChatGPT to stop trying to build one script and instead create small, modular scripts to validate inputs and outputs.

We broke the workflow down into three distinct, testable scripts.

Script 1 (Infrastructure)
A one time setup script to create two necessary files on the router: `File A` to temporarily store raw Telegram API messages, and `File B` to act as a persistent log of the last processed Chat ID.

Script 2 (The Fetcher)
A dedicated script with the sole purpose of pulling the latest json data from Telegram and writing it blindly into `File A`.

Script 3 (The Processor)
The logic core. This script reads `File A`, extracts the command (`!<ScriptName>`), checks the message ID against the log in `File B` to ensure it hasn't run before, executes the command, and updates `File B`.



### Phase 3: Challenging the AI "Hallucinations"



The modular approach immediately paid off. We could verify that Script 1 created files correctly and that Script 2 was successfully pulling data from Telegram.

The issue was isolated entirely to Script 3. It was failing to handle scenarios where there were no new messages from Telegram, and it struggled to write the updated ID back to `File B`.

When I presented these specific errors to ChatGPT, its response was telling. It suggested rewriting parts of Script 1 and Script 2 (the two scripts we had already verified were working perfectly).

The Human in the Loop

I refused. I challenged the AI: *Why replace parts of Script 1 & 2 when they are verified working? The error is clearly isolated to Script 3.*

ChatGPT immediately "backed down," acknowledged the logic, and refocused its efforts solely on fixing Script 3. Within minutes, the modular system was working flawlessly.

The final, working modular scripts resulting from this session can be found in this repository: <https://github.com/dermawas/Mikrotik-TelegramCommandParser>



### The Workflow Takeaway



Working with AI on complex technical implementations is rarely a "set it and forget it" process. It requires a shift in mindset from "coder" to "architect."

My key observations from this two day build:

1. Define Constraints Early: Don't just ask for a feature; ask for the constraints surrounding that feature (e.g., "it must only run once").
2. Demand Modularity: AI tends to build brittle monoliths. Force it to build small, verifiable components. If you can't test an input and an output in isolation, the script is too big.
3. Keep a Tight Rein: AI will "hallucinate" solutions that involve tearing down working infrastructure. As the user, you must maintain the mental model of the project and firmly refuse suggestions that defy logic or break established, working components.
