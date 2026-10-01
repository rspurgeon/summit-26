---
title: Summit AI Developer Portal
description: Explore our AI APIs, choose a model, and send your first request.
---

# Build with Summit AI

Generate text through one OpenAI-compatible chat endpoint. Choose the model
that fits your request, then use the API reference and examples to get started.

## Explore the APIs

- [Browse all APIs](/apis)
- [Chat Completions API](/apis/summit-chat-completions) — request and response
  schemas, streaming, and specification versions.
- [Getting started](/apis/summit-chat-completions/docs/getting-started) — send
  your first request with curl or the repository's chat script.

## Choose a model

| Gateway alias | OpenAI model | Use |
| --- | --- | --- |
| `demo-chat` | `gpt-4.1-mini` | General text generation |
| `nano-chat` | `gpt-4.1-nano` | Lower-cost text generation |

Both models use `POST /v1/chat/completions`. Select the alias in the request's
`model` field. The current **1.1.0** specification covers both aliases; **1.0.0**
documents the original mini-only contract.

The gateway runs on your local Docker host at `http://127.0.0.1:8000`.
Run API requests from that host; the gateway supplies the OpenAI credential.
