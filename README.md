# ExZcal

Elixir client for [zcal](https://zcal.co) scheduling.

zcal has **no public REST API** — its team shipped webhooks in its place — so
there is nothing here to authenticate and no HTTP client to configure. What is
left is the part that actually needs care: verifying and parsing the webhooks
zcal sends you, and building booking URLs that behave correctly when embedded.

Everything is a pure function over data you already have, and the library has
**no runtime dependencies**.

Built in the same style as its sibling clients (small focused modules,
`{:ok, _}` / `{:error, _}` returns, structs that keep the original payload on
`raw`).

## Installation

```elixir
def deps do
  [
    {:ex_zcal, git: "https://github.com/drdray1/ex_zcal.git", tag: "0.1.1"}
  ]
end
```

## Usage

### Receiving a booking

zcal `POST`s on three triggers — `event.created`, `event.rescheduled`, and
`event.cancelled` — to a single endpoint. Verify the signature against the
**raw** request body, then parse the decoded params:

```elixir
with :ok <- ExZcal.verify(raw_body, signature, secret),
     {:ok, event} <- ExZcal.parse(params) do
  invitee = ExZcal.Event.invitee(event)

  %{
    booking_id: event.id,
    status: event.type,                      # :created | :rescheduled | :cancelled
    name: invitee.name,                      # "Jane Doe"
    email: invitee.email,                    # "jane.doe@gmail.com"
    starts_at: event.starts_at,              # ~U[2025-02-12 20:30:00.000Z]
    ends_at: ExZcal.Event.ends_at(event),    # ~U[2025-02-12 21:00:00.000Z]
    invite_id: ExZcal.Event.invite_id(event) # "aZbYc_8" — which link was booked
  }
end
```

The wire payload nests the booking under `"data"` and puts the person who booked
inside `"attendees"` — the entry whose type is `"invitee"` — rather than at the
top level. That is easy to get wrong from the docs alone, so reach for the
helpers rather than indexing the map:

```elixir
ExZcal.Event.invitee(event)   # the person who booked
ExZcal.Event.guests(event)    # anyone they brought
ExZcal.Event.host(event)      # for round robin, the assigned team member
ExZcal.Event.answers(event)   # the invitee's custom-question answers
ExZcal.Event.answer(event, "property_id")   # one answer, by question
```

Checkbox questions arrive as a list where zcal's schema says string, so
`ExZcal.Answer` normalizes every answer to `values` (a list) and `text/1`
(comma-joined).

### Verification

| Detail | Value |
| --- | --- |
| Header | `x-zcal-webhook-signature` |
| Algorithm | HMAC-SHA256 over the raw request body |
| Encoding | hex (base64 and a `sha256=` prefix are also accepted) |
| Secret | optional in zcal — set one, and treat a missing signature as a failure |

`verify/3` compares in constant time and returns `:ok` or `{:error, reason}`,
where `reason` is `:missing_signature`, `:missing_secret`, or
`:invalid_signature`. It fails closed: with no secret configured, nothing
verifies.

Sign against the raw body, not a re-encoded map — re-serializing can reorder
keys or change whitespace and will not match. In Phoenix that means caching the
body with a custom `Plug.Parsers` `:body_reader` on the webhook path.

### Sending someone to book

```elixir
ExZcal.booking_url("aZbYc_8", name: "Jane", email: "jane@example.com")
#=> "https://zcal.co/i/aZbYc_8?email=jane%40example.com&name=Jane"

ExZcal.booking_url("aZbYc_8",
  start_date: ~U[2026-01-01 18:30:00Z],
  timezone: "America/Phoenix",
  guests: ["adam@example.com", "bob@example.com"],
  answers: ["Blue", ["Option 1", "Option 3"]],
  utm: [campaign: "spring", content: "home:H-1001"]
)
```

Custom-question answers are positional (`a0`, `a1`, …) in the order the
questions appear on the invite; dropdown and checkbox values must match the
configured options exactly. zcal silently ignores parameters it cannot use.

### Embedding

This is the part worth reading twice. zcal serves `X-Frame-Options: DENY` on
**every** booking path except `/i/<id>` and `/emb/<slug>`, so dropping an
ordinary booking link into an `<iframe>` renders a blank box.

```elixir
ExZcal.embed_url({:slug, "30min"})
#=> "https://zcal.co/emb/30min?embed=1&embedType=inline&embedVersion=1.0.2"

ExZcal.framable?("https://zcal.co/jane/30min")   #=> false
ExZcal.framable?("https://zcal.co/i/aZbYc_8")    #=> true
```

`embed_url/2` applies the same `/emb` rewrite zcal's own widget does and adds
the parameters it sends. For a responsive embed use the official widget, which
auto-resizes to the booking page's height — a plain iframe cannot:

```elixir
ExZcal.embed_snippet("aZbYc_8", label: "Book a visit")
```

## Referencing an invite

| Form | Resolves to |
| --- | --- |
| `"aZbYc_8"` | `/i/aZbYc_8` — a bare string is an **invite id** |
| `{:invite, "aZbYc_8"}` | `/i/aZbYc_8` |
| `{:slug, "30min"}` | `/30min` |
| `"jane/30min"`, `"t/acme/intro"` | used as given |
| `"https://meet.acme.com/30min"` | used as-is, so custom domains work |

A bare string means an invite id rather than a slug because the two are
indistinguishable and only one is safe: `/i/<id>` is framable and survives
renaming the pretty slug. Pass `:base_url` for a custom domain.

## What zcal does not document

The payload is unversioned and parsing here is deliberately permissive, but
verify these against a real booking before depending on them:

- whether `event.id` is **stable across a reschedule or cancellation** — it is
  the natural idempotency key, but zcal does not say, and there is no
  `rescheduledFrom` field to fall back on
- where, or whether, **UTM parameters** reach the payload. zcal says it forwards
  them but they appear nowhere in its published schema, so `event.utm` searches
  several plausible locations and may simply be empty. Its redirect-on-booking
  URL *is* documented to carry them, as a fallback attribution channel
- the **retry policy** and the response zcal expects. Answer quickly and stay
  idempotent: zcal flags failing endpoints and may disable them

Webhooks are also a paid feature, though zcal's pricing page does not say which
tier unlocks them.

## Development

```sh
mix deps.get
mix test --cover
mix credo
mix format --check-formatted
```

## License

MIT.
