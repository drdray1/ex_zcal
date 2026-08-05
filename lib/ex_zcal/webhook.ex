defmodule ExZcal.Webhook do
  @moduledoc """
  Receiving zcal booking webhooks: verifying the signature and parsing the body.

  zcal `POST`s here on three triggers — `event.created`, `event.rescheduled`,
  and `event.cancelled` — and a single endpoint receives all three (there is no
  per-event subscription). A webhook configured at **user** level receives
  bookings from all of that user's invite links; one configured at **team**
  level receives only that team's collective and round-robin invites.

  ## Verifying

  When you set a secret key on the webhook, zcal signs the request body with
  HMAC-SHA256 and sends the hex digest in the `x-zcal-webhook-signature` header.
  Verify against the **raw** request body — re-encoding a parsed body can change
  key order or whitespace and will not match:

      case ExZcal.Webhook.verify(raw_body, signature, secret) do
        :ok -> handle(params)
        {:error, _reason} -> send_resp(conn, 401, "invalid signature")
      end

  The signature is only sent if a secret is configured, so treat a missing
  signature as a failure rather than a skip.

  ## Parsing

      {:ok, event} = ExZcal.Webhook.parse(params)

  Answer quickly and stay idempotent: zcal flags endpoints that fail and may
  disable them, and it documents no retry policy or ordering guarantees.
  """

  import Bitwise, only: [bor: 2, bxor: 2]

  alias ExZcal.Event

  @signature_header "x-zcal-webhook-signature"

  @types %{
    "event.created" => :created,
    "event.rescheduled" => :rescheduled,
    "event.cancelled" => :cancelled
  }

  @doc "The header zcal puts the payload signature in."
  @spec signature_header() :: String.t()
  def signature_header, do: @signature_header

  @doc """
  Verifies a webhook's HMAC-SHA256 signature against the raw request body.

  `signature` is the `x-zcal-webhook-signature` header value; pass `nil` when it
  is absent. Comparison is constant-time. zcal sends a bare hex digest, but a
  `sha256=` prefix and base64 digests are accepted too so a future change in
  encoding does not start silently rejecting deliveries.

  Returns `:ok`, or `{:error, :missing_signature | :missing_secret | :invalid_signature}`.
  """
  @spec verify(binary(), String.t() | nil, String.t() | nil) ::
          :ok | {:error, :missing_signature | :missing_secret | :invalid_signature}
  def verify(raw_body, signature, secret)

  def verify(_raw_body, _signature, secret) when secret in [nil, ""],
    do: {:error, :missing_secret}

  def verify(_raw_body, signature, _secret) when signature in [nil, ""],
    do: {:error, :missing_signature}

  def verify(raw_body, signature, secret) when is_binary(raw_body) do
    mac = :crypto.mac(:hmac, :sha256, secret, raw_body)
    provided = strip_prefix(signature)

    expected = [
      Base.encode16(mac, case: :lower),
      Base.encode64(mac)
    ]

    if Enum.any?(expected, &secure_compare(&1, provided)),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  @doc """
  Parses a decoded webhook body into an `ExZcal.Event`.

  Takes the already-decoded JSON map (what Plug hands you in `params`), not a
  raw string. The wire format nests the booking under `"data"`, so reach for the
  helpers on `ExZcal.Event` rather than indexing the map yourself.

  Returns `{:error, {:unhandled_type, type}}` for a trigger this library does not
  model, and `{:error, :invalid_payload}` for anything that is not a webhook body.

      {:ok, event} = ExZcal.Webhook.parse(params)
      event.type                            #=> :created
      ExZcal.Event.invitee(event).email     #=> "jane.doe@gmail.com"
  """
  @spec parse(map()) ::
          {:ok, Event.t()} | {:error, :invalid_payload | {:unhandled_type, String.t()}}
  def parse(%{"data" => %{} = data} = payload) do
    case Map.fetch(@types, payload["type"]) do
      {:ok, type} -> {:ok, Event.new(payload, data, type)}
      :error -> {:error, {:unhandled_type, payload["type"]}}
    end
  end

  def parse(_payload), do: {:error, :invalid_payload}

  @doc "The webhook trigger strings this library understands."
  @spec types() :: [String.t()]
  def types, do: Map.keys(@types)

  defp strip_prefix("sha256=" <> rest), do: rest
  defp strip_prefix(signature), do: signature

  # Constant-time comparison, written out rather than pulled from :crypto or
  # Plug.Crypto so the library keeps zero runtime dependencies and no minimum
  # OTP beyond what Elixir itself requires. Length is compared up front, which
  # leaks only the digest length — a constant.
  defp secure_compare(expected, provided) when byte_size(expected) == byte_size(provided),
    do: compare_bytes(expected, provided, 0) == 0

  defp secure_compare(_expected, _provided), do: false

  defp compare_bytes(<<a, rest_a::binary>>, <<b, rest_b::binary>>, acc),
    do: compare_bytes(rest_a, rest_b, bor(acc, bxor(a, b)))

  defp compare_bytes(<<>>, <<>>, acc), do: acc
end
