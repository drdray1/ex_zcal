defmodule ExZcal.EventTest do
  use ExUnit.Case, async: true

  alias ExZcal.{Answer, Event, Fixtures, Webhook}

  defp event(overrides \\ %{}) do
    {:ok, event} = Webhook.parse(Fixtures.payload(overrides))
    event
  end

  describe "invitee/1 and guests/1" do
    test "picks the booker out of the attendees list" do
      invitee = Event.invitee(event())

      assert invitee.name == "Jane Doe"
      assert invitee.email == "jane.doe@gmail.com"
      assert invitee.timezone == "America/New_York"
      assert invitee.type == :invitee
    end

    test "separates guests from the booker" do
      assert [guest] = Event.guests(event())
      assert guest.email == "guest@example.com"
      assert guest.type == :guest
    end

    test "falls back to the first attendee when no type is given" do
      event = event(%{"data" => %{"attendees" => [%{"email" => "only@example.com"}]}})

      assert Event.invitee(event).email == "only@example.com"
      assert Event.guests(event) == []
    end

    test "passes an unrecognized attendee type through untouched" do
      event = event(%{"data" => %{"attendees" => [%{"email" => "x@y.z", "type" => "observer"}]}})

      assert [%{type: "observer"}] = event.attendees
    end
  end

  describe "answers/1 and answer/2" do
    test "returns the booker's answers in order" do
      assert [first, second] = Event.answers(event())

      assert first.question == "What is your favorite color?"
      assert first.values == ["Blue"]
      assert second.values == ["Option 1", "Option 3"]
    end

    test "normalizes a checkbox answer's list into display text" do
      assert Event.answer(event(), "Select all options you would like:") == "Option 1, Option 3"
    end

    test "matches the question case-insensitively and ignores surrounding space" do
      assert Event.answer(event(), "  what is YOUR favorite color?  ") == "Blue"
    end

    test "returns nil for a question that was not answered" do
      assert Event.answer(event(), "shoe size") == nil
    end

    test "handles answers with unusual value types without raising" do
      event =
        event(%{
          "data" => %{
            "attendees" => [
              %{
                "email" => "x@y.z",
                "type" => "invitee",
                "customQuestionAnswers" => [
                  %{"question" => "count", "answer" => 3},
                  %{"question" => "agreed", "answer" => true},
                  %{"question" => "empty", "answer" => nil},
                  %{"label" => "alt-key", "value" => "used"},
                  %{"question" => "weird", "answer" => %{"a" => 1}}
                ]
              }
            ]
          }
        })

      assert Event.answer(event, "count") == "3"
      assert Event.answer(event, "agreed") == "true"
      assert Event.answer(event, "empty") == ""
      assert Event.answer(event, "alt-key") == "used"
      assert Event.answer(event, "weird") =~ "a"
    end

    test "Answer.text/1 joins multiple values" do
      assert Answer.text(%Answer{question: "q", values: ["a", "b"]}) == "a, b"
      assert Answer.text(%Answer{question: "q", values: []}) == ""
    end
  end

  describe "host/1 and invite_id/1" do
    test "returns the first host" do
      assert Event.host(event()).email == "john.smith@gmail.com"
    end

    test "returns nil when there are no hosts" do
      assert Event.host(event(%{"data" => %{"hosts" => []}})) == nil
    end

    test "returns the invite id used to map a booking back to its link" do
      assert Event.invite_id(event()) == "aZbYc_8"
    end
  end

  describe "ends_at/1" do
    test "adds the duration to the start" do
      assert DateTime.to_iso8601(Event.ends_at(event())) == "2025-02-12T21:00:00.000Z"
    end

    test "is nil without a usable start or duration" do
      assert Event.ends_at(event(%{"data" => %{"duration" => nil}})) == nil
      assert Event.ends_at(event(%{"data" => %{"startDate" => nil}})) == nil
    end
  end

  describe "utm" do
    test "is empty when the payload carries no UTM parameters" do
      assert event().utm == %{}
    end

    test "picks UTM parameters up from the envelope" do
      assert event(%{"utm_campaign" => "spring"}).utm == %{campaign: "spring"}
    end

    test "picks them up from the event data" do
      event = event(%{"data" => %{"utm_source" => "site", "utm_content" => "home:H-1"}})

      assert event.utm == %{source: "site", content: "home:H-1"}
    end

    test "picks them up from a nested utm, tracking or metadata map" do
      assert event(%{"data" => %{"utm" => %{"utm_medium" => "web"}}}).utm == %{medium: "web"}
      assert event(%{"data" => %{"tracking" => %{"utm_term" => "t"}}}).utm == %{term: "t"}

      assert event(%{"data" => %{"metadata" => %{"utm_campaign" => "m"}}}).utm ==
               %{campaign: "m"}
    end

    test "ignores blank and non-string values" do
      event = event(%{"data" => %{"utm_campaign" => "", "utm_source" => 5}})

      assert event.utm == %{}
    end
  end
end
