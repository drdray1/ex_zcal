defmodule ExZcal do
  @moduledoc """
  Elixir client for [zcal](https://zcal.co) scheduling.

  zcal has **no public REST API** — its team shipped webhooks in its place — so
  there is nothing here to authenticate and no HTTP client to configure. What is
  left is the part that actually needs care: verifying and parsing the webhooks
  zcal sends you, and building booking URLs that behave correctly when embedded.
  Everything in this library is a pure function over data you already have, and
  it has no runtime dependencies.

  ## Receiving a booking

  Verify against the raw request body, then parse the decoded params:

      with :ok <- ExZcal.verify(raw_body, signature, secret),
           {:ok, event} <- ExZcal.parse(params) do
        invitee = ExZcal.Event.invitee(event)

        %{
          booking_id: event.id,
          status: event.type,               # :created | :rescheduled | :cancelled
          name: invitee.name,
          email: invitee.email,
          starts_at: event.starts_at,
          invite_id: ExZcal.Event.invite_id(event)
        }
      end

  The wire payload nests the booking under `"data"` and puts the person who
  booked inside `"attendees"` (the entry whose type is `"invitee"`), which is
  easy to get wrong from the docs alone — `ExZcal.Event.invitee/1`,
  `guests/1`, `host/1`, `answers/2`, and `ends_at/1` handle that shape for you.
  The untouched payload stays on `event.raw`.

  ## Sending someone to book

      ExZcal.booking_url("aZbYc_8", name: "Jane", email: "jane@example.com")

  To embed a booking page, use `embed_url/2` or `embed_snippet/2` rather than
  the plain booking URL. zcal serves `X-Frame-Options: DENY` everywhere except
  `/i/<id>` and `/emb/<slug>`, so an ordinary link in an `<iframe>` renders
  blank; `embed_url/2` applies the same `/emb` rewrite zcal's own widget does.

  ## What zcal does not document

  The payload is unversioned and parsing here is deliberately permissive, but
  three things are worth verifying against a real booking before you depend on
  them:

    * whether `event.id` is stable across a reschedule or cancellation (it is
      the natural idempotency key, but zcal does not say)
    * where — or whether — UTM parameters land in the payload; zcal says it
      forwards them but they appear nowhere in its published schema, so
      `event.utm` searches several plausible locations and may be empty
    * the retry policy and the response zcal expects

  See `ExZcal.Webhook` and `ExZcal.Link` for the full detail.
  """

  alias ExZcal.{Link, Webhook}

  defdelegate verify(raw_body, signature, secret), to: Webhook
  defdelegate parse(payload), to: Webhook
  defdelegate signature_header(), to: Webhook

  defdelegate booking_url(invite_ref, opts \\ []), to: Link
  defdelegate embed_url(invite_ref, opts \\ []), to: Link
  defdelegate embed_snippet(invite_ref, opts \\ []), to: Link
  defdelegate framable?(url), to: Link
end
