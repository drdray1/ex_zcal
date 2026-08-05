defmodule ExZcal.WebhookTest do
  use ExUnit.Case, async: true

  alias ExZcal.{Event, Fixtures, Webhook}

  doctest ExZcal.Webhook

  describe "verify/3" do
    test "accepts a correct hex signature over the raw body" do
      body = Fixtures.raw_payload()

      assert Webhook.verify(body, Fixtures.sign(body, Fixtures.secret()), Fixtures.secret()) ==
               :ok
    end

    test "accepts a sha256= prefixed signature" do
      body = Fixtures.raw_payload()
      signature = "sha256=" <> Fixtures.sign(body, Fixtures.secret())

      assert Webhook.verify(body, signature, Fixtures.secret()) == :ok
    end

    test "accepts a base64 digest" do
      body = Fixtures.raw_payload()
      signature = :hmac |> :crypto.mac(:sha256, Fixtures.secret(), body) |> Base.encode64()

      assert Webhook.verify(body, signature, Fixtures.secret()) == :ok
    end

    test "rejects a signature made with the wrong secret" do
      body = Fixtures.raw_payload()
      signature = Fixtures.sign(body, "not-the-secret")

      assert Webhook.verify(body, signature, Fixtures.secret()) == {:error, :invalid_signature}
    end

    test "rejects a signature for a different body" do
      signature = Fixtures.sign("{}", Fixtures.secret())

      assert Webhook.verify(Fixtures.raw_payload(), signature, Fixtures.secret()) ==
               {:error, :invalid_signature}
    end

    test "rejects a malformed signature of the wrong length" do
      assert Webhook.verify(Fixtures.raw_payload(), "deadbeef", Fixtures.secret()) ==
               {:error, :invalid_signature}
    end

    test "fails closed when no secret is configured" do
      body = Fixtures.raw_payload()

      assert Webhook.verify(body, Fixtures.sign(body, "x"), nil) == {:error, :missing_secret}
      assert Webhook.verify(body, Fixtures.sign(body, "x"), "") == {:error, :missing_secret}
    end

    test "fails when the signature header is absent" do
      assert Webhook.verify(Fixtures.raw_payload(), nil, Fixtures.secret()) ==
               {:error, :missing_signature}

      assert Webhook.verify(Fixtures.raw_payload(), "", Fixtures.secret()) ==
               {:error, :missing_signature}
    end
  end

  describe "parse/1" do
    test "parses the documented sample payload" do
      assert {:ok, %Event{} = event} = Webhook.parse(Fixtures.payload())

      assert event.id == "sample-event-id"
      assert event.type == :created
      assert event.name == "Jane Doe and John Smith"
      assert event.duration == 30
      assert event.cancelled == false
      assert DateTime.to_iso8601(event.starts_at) == "2025-02-12T20:30:00.000Z"
      assert DateTime.to_iso8601(event.webhook_sent_at) == "2025-02-09T14:46:11.469Z"
    end

    test "parses the invite, hosts, location and team" do
      {:ok, event} = Webhook.parse(Fixtures.payload())

      assert event.invite.id == "aZbYc_8"
      assert event.invite.name == "30 minute call"
      assert event.invite.invite_type == "one_on_one"
      assert event.invite.description == "Meet with John for 30 minutes!"

      assert [%{name: "John Smith", email: "john.smith@gmail.com"}] = event.hosts

      assert event.location.type == "zoom"
      assert event.location.meeting_id == "123456789"
      assert event.location.meeting_passcode == "Ac0QRP"
      assert event.location.meeting_url =~ "zoom.us"

      assert event.team == nil
    end

    test "parses a team when the invite is a team invite" do
      payload = Fixtures.payload(%{"data" => %{"team" => %{"id" => "t_1", "name" => "Sales"}}})

      {:ok, event} = Webhook.parse(payload)

      assert event.team.id == "t_1"
      assert event.team.name == "Sales"
    end

    test "keeps the untouched payload on raw" do
      {:ok, event} = Webhook.parse(Fixtures.payload())

      assert event.raw == Fixtures.payload()
    end

    test "maps each webhook trigger to a type" do
      for {trigger, type} <- [
            {"event.created", :created},
            {"event.rescheduled", :rescheduled},
            {"event.cancelled", :cancelled}
          ] do
        {:ok, event} = Webhook.parse(Fixtures.payload(%{"type" => trigger}))
        assert event.type == type
      end
    end

    test "rejects a trigger it does not model" do
      assert Webhook.parse(Fixtures.payload(%{"type" => "event.exploded"})) ==
               {:error, {:unhandled_type, "event.exploded"}}
    end

    test "rejects anything that is not a webhook body" do
      assert Webhook.parse(%{"type" => "event.created"}) == {:error, :invalid_payload}
      assert Webhook.parse(%{}) == {:error, :invalid_payload}
      assert Webhook.parse("nope") == {:error, :invalid_payload}
    end

    test "tolerates missing, empty and malformed sections" do
      payload =
        Fixtures.payload(%{
          "created_at" => nil,
          "data" => %{
            "startDate" => "not-a-date",
            "duration" => "45",
            "invite" => nil,
            "location" => "unexpected",
            "hosts" => nil,
            "attendees" => []
          }
        })

      assert {:ok, event} = Webhook.parse(payload)

      assert event.starts_at == nil
      assert event.webhook_sent_at == nil
      # A stringified duration is still usable.
      assert event.duration == 45
      assert event.invite == nil
      assert event.location == nil
      assert event.hosts == []
      assert event.attendees == []
      assert Event.invitee(event) == nil
      assert Event.answers(event) == []
      assert Event.ends_at(event) == nil
      assert Event.invite_id(event) == nil
    end

    test "drops a duration it cannot make sense of" do
      payload = Fixtures.payload(%{"data" => %{"duration" => "soon"}})

      assert {:ok, %{duration: nil}} = Webhook.parse(payload)
    end
  end

  describe "types/0 and signature_header/0" do
    test "expose the wire constants" do
      assert Enum.sort(Webhook.types()) == [
               "event.cancelled",
               "event.created",
               "event.rescheduled"
             ]

      assert Webhook.signature_header() == "x-zcal-webhook-signature"
    end
  end
end
