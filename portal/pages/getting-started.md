---
title: Getting started
description: Send chat requests to the local Summit AI Gateway.
---

# Send your first chat request

Run these commands on the machine hosting the Summit AI Gateway Docker data
plane. Its HTTP endpoint listens on `127.0.0.1:8000`. The hosted developer
portal publishes the documentation; requests run from your local terminal.

## Choose a model

Set `model` to `demo-chat` for OpenAI `gpt-4.1-mini`, or `demo-chat-nano` for
OpenAI `gpt-4.1-nano`. The gateway supplies the provider credential. This local
deployment has no caller authentication, so clients only send a JSON body.

```bash
curl --fail-with-body --silent --show-error --max-time 60 \
  http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"demo-chat-nano","messages":[{"role":"user","content":"Give me a short greeting."}],"max_tokens":32}'
```

Read the reply from `choices[0].message.content`. The returned `model` may be
the upstream OpenAI model identifier rather than the gateway alias.

From the Summit repository, you can also use the terminal client:

```bash
./chat.sh --model demo-chat-nano "Give me a short greeting."
./chat.sh --model demo-chat "Explain AI gateways in two sentences."
```

## Stream a reply

Set `stream` to `true` and use `--no-buffer` to receive server-sent events:

```bash
curl --fail-with-body --silent --show-error --no-buffer --max-time 60 \
  http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"demo-chat","messages":[{"role":"user","content":"Give me a short greeting."}],"max_tokens":32,"stream":true}'
```

Each JSON data event can contribute text in `choices[0].delta.content`.
The final event is `data: [DONE]`.

## Understand errors

An unknown model alias can return `404` because no gateway model route matches.
An invalid request can return `400`; provider authentication failures can
return `401`; quota or rate limits can return `429`. Inspect the response
body for details before retrying. Provider errors can appear under `error`,
while gateway errors can use `message`.

Browse the [API reference](/apis) for the supported text request parameters,
completion response, and streaming event schemas.
