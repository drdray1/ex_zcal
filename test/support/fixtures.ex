defmodule ExZcal.Fixtures do
  @moduledoc """
  Sample webhook payloads.

  `raw_payload/0` is zcal's published example, kept verbatim as JSON so the
  parser is exercised against the real wire format — including the details that
  are easy to get wrong: everything nested under `data`, the booker living in
  `attendees` rather than at the top level, and a checkbox answer arriving as a
  list where the schema says string.
  """

  @doc "zcal's documented sample payload, as the raw JSON string it arrives as."
  def raw_payload do
    """
    {
      "type": "event.created",
      "created_at": "2025-02-09T14:46:11.469Z",
      "data": {
        "id": "sample-event-id",
        "startDate": "2025-02-12T20:30:00.000Z",
        "duration": 30,
        "cancelled": false,
        "eventName": "Jane Doe and John Smith",
        "location": {
          "locationType": "zoom",
          "onlineMeeting": {
            "url": "https://us05web.zoom.us/j/123456789?pwd=AbDeFR2Mebh0vioMYCvLsb2RA3fR.1",
            "id": "123456789",
            "passcode": "Ac0QRP"
          }
        },
        "hosts": [{ "name": "John Smith", "email": "john.smith@gmail.com" }],
        "attendees": [
          {
            "name": "Jane Doe",
            "email": "jane.doe@gmail.com",
            "timezone": "America/New_York",
            "type": "invitee",
            "customQuestionAnswers": [
              { "question": "What is your favorite color?", "answer": "Blue" },
              { "question": "Select all options you would like:", "answer": ["Option 1", "Option 3"] }
            ]
          },
          { "email": "guest@example.com", "type": "guest" }
        ],
        "invite": {
          "id": "aZbYc_8",
          "name": "30 minute call",
          "inviteType": "one_on_one",
          "description": "Meet with John for 30 minutes!"
        }
      }
    }
    """
  end

  @doc "The decoded sample payload, as Plug would hand it to a controller."
  def payload, do: Jason.decode!(raw_payload())

  @doc """
  The sample payload with `overrides` merged into its envelope. Pass a map under
  `"data"` to override event fields (shallow-merged onto the sample's data).
  """
  def payload(overrides) when is_map(overrides) do
    base = payload()

    case Map.pop(overrides, "data") do
      {nil, envelope} ->
        Map.merge(base, envelope)

      {data, envelope} ->
        base |> Map.merge(envelope) |> Map.put("data", Map.merge(base["data"], data))
    end
  end

  @doc "The signature zcal would send for `body` given `secret`."
  def sign(body, secret) do
    :hmac |> :crypto.mac(:sha256, secret, body) |> Base.encode16(case: :lower)
  end

  @doc "The secret used across the tests."
  def secret, do: "test-webhook-secret"
end
