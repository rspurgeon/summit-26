---
title: Build with Summit AI
description: Two OpenAI models, one chat API. Explore the reference and send your first request.
---

::page-section
  ::page-hero
  ---
  title-tag: h1
  text-align: center
  ---
  #title
  Two models. One chat API.

  #description
  Build chat experiences with Summit AI Gateway. Choose a general-purpose model or a lower-cost option using the same OpenAI-compatible endpoint.

  #actions
    ::button
    ---
    to: /getting-started
    size: large
    ---
    Send your first request
    ::
  ::
::

## Choose your model

| Gateway alias | OpenAI model | Use it for |
| --- | --- | --- |
| `demo-chat` | `gpt-4.1-mini` | General text generation and conversation |
| `demo-chat-nano` | `gpt-4.1-nano` | Simple prompts and lower-cost text generation |

Both models support text chat generation through `POST /v1/chat/completions`.
Receive a complete assistant reply or stream the reply as server-sent events.

## Explore the API

The current **1.1.0** specification documents both model aliases. The **1.0.0**
specification preserves the original `demo-chat` contract.

::apis-list
---
cta-text: View reference
page-size: 3
pagination: false
---
::

## Run it locally

The gateway is available at `http://127.0.0.1:8000` on the machine hosting
the Docker data plane. Use the terminal examples in [Getting started](/getting-started).
The gateway supplies the OpenAI credential for your request; usage is billed
to its configured provider account.
