# Chat with Summit AI

Send OpenAI-compatible text chat requests to the Summit AI Gateway. Select a
model by its gateway alias in the JSON request body:

| Gateway alias | OpenAI target | Use |
| --- | --- | --- |
| `demo-chat` | `gpt-4.1-mini` | General text generation |
| `nano-chat` | `gpt-4.1-nano` | Lower-cost text generation |

Specification version **1.0.0** documents the original mini-only contract.
Version **1.1.0** adds the nano alias and is the current reference. Both use
`POST /v1/chat/completions`. These are documentation versions; both aliases
are available through the same running gateway.

## Send a request

The gateway currently runs locally. Run this command on the machine hosting
its Docker data plane at port 8000. The public portal provides documentation;
its hosted website does not turn the local gateway into a public endpoint.

```bash
curl --fail-with-body --silent --show-error --max-time 60 \
  http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"nano-chat","messages":[{"role":"user","content":"Give me a short greeting."}],"max_tokens":32}'
```

Read the assistant reply from `choices[0].message.content`. Change `model` to
`demo-chat` to use the mini model. The gateway supplies the OpenAI credential;
clients do not send an OpenAI key. No client authentication is configured for
this local deployment. Requests consume the provider account's tokens.

From the Summit repository, the same request can be sent with:

```bash
AIGW_MODEL=nano-chat bash chat.sh "Give me a short greeting."
```

## Stream the reply

Add `"stream": true` and use `curl --no-buffer` to consume server-sent events.
Each JSON chunk contributes text in `choices[0].delta.content`; the stream ends
with `data: [DONE]`. The specification includes request, response and chunk
schemas for the text chat contract.

Unknown aliases do not match a model route. Invalid requests, upstream rate
limits, quota limits or provider failures produce error responses. Inspect the
response body before retrying.
