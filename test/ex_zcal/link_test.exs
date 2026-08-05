defmodule ExZcal.LinkTest do
  use ExUnit.Case, async: true

  alias ExZcal.Link

  defp query(url), do: url |> URI.parse() |> Map.get(:query) |> URI.decode_query()
  defp path(url), do: url |> URI.parse() |> Map.get(:path)

  describe "booking_url/2" do
    test "addresses a bare invite id as /i/<id>" do
      assert Link.booking_url("aZbYc_8") == "https://zcal.co/i/aZbYc_8"
      assert Link.booking_url({:invite, "aZbYc_8"}) == "https://zcal.co/i/aZbYc_8"
    end

    test "addresses an explicit slug as a bare path" do
      assert Link.booking_url({:slug, "30min"}) == "https://zcal.co/30min"
      assert Link.booking_url({:slug, "/30min"}) == "https://zcal.co/30min"
    end

    test "leaves an explicit path alone" do
      assert Link.booking_url("i/aZbYc_8") == "https://zcal.co/i/aZbYc_8"
      assert Link.booking_url("jane/30min") == "https://zcal.co/jane/30min"
      assert Link.booking_url("t/acme/intro") == "https://zcal.co/t/acme/intro"
    end

    test "tolerates a leading slash" do
      assert Link.booking_url("/i/aZbYc_8") == "https://zcal.co/i/aZbYc_8"
    end

    test "uses a full URL as given, so custom domains work" do
      assert Link.booking_url("https://meet.acme.com/30min") == "https://meet.acme.com/30min"
      assert Link.booking_url("http://localhost:4000/30min") == "http://localhost:4000/30min"
    end

    test "honours a custom base_url" do
      assert Link.booking_url({:slug, "30min"}, base_url: "https://meet.acme.com") ==
               "https://meet.acme.com/30min"

      assert Link.booking_url("aZbYc_8", base_url: "https://meet.acme.com") ==
               "https://meet.acme.com/i/aZbYc_8"
    end

    test "prefills the booker's details" do
      params = Link.booking_url("x", name: "Jane Doe", email: "jane@example.com") |> query()

      assert params["name"] == "Jane Doe"
      assert params["email"] == "jane@example.com"
    end

    test "formats a DateTime start_date and passes a string through" do
      {:ok, datetime, _} = DateTime.from_iso8601("2026-01-01T18:30:00Z")

      assert query(Link.booking_url("x", start_date: datetime))["startDate"] ==
               "2026-01-01T18:30:00Z"

      assert query(Link.booking_url("x", start_date: "2026-01-01T18:30:00.000Z"))["startDate"] ==
               "2026-01-01T18:30:00.000Z"
    end

    test "passes the remaining scalar prefill options through" do
      params =
        Link.booking_url("x",
          timezone: "America/Phoenix",
          duration: 60,
          location_index: 1,
          sms_phone: "+15555555555"
        )
        |> query()

      assert params["timezone"] == "America/Phoenix"
      assert params["duration"] == "60"
      assert params["locationIndex"] == "1"
      assert params["smsPhone"] == "+15555555555"
    end

    test "comma-joins a guest list" do
      assert query(Link.booking_url("x", guests: ["a@x.com", "b@x.com"]))["guests"] ==
               "a@x.com,b@x.com"

      assert query(Link.booking_url("x", guests: "a@x.com"))["guests"] == "a@x.com"
    end

    test "numbers answers positionally and comma-joins checkbox values" do
      params = Link.booking_url("x", answers: ["Blue", ["Option 1", "Option 3"]]) |> query()

      assert params["a0"] == "Blue"
      assert params["a1"] == "Option 1,Option 3"
    end

    test "accepts answers as a map keyed by question index" do
      params = Link.booking_url("x", answers: %{0 => "Blue", 3 => "Green"}) |> query()

      assert params["a0"] == "Blue"
      assert params["a3"] == "Green"
    end

    test "prefixes UTM options, from a keyword list or a map" do
      assert query(Link.booking_url("x", utm: [campaign: "spring", content: "home:H-1"])) ==
               %{"utm_campaign" => "spring", "utm_content" => "home:H-1"}

      assert query(Link.booking_url("x", utm: %{source: "site"})) == %{"utm_source" => "site"}
    end

    test "merges extra params last and preserves ones already on a full URL" do
      assert query(Link.booking_url("x", params: %{"ref" => "email"}))["ref"] == "email"

      params = Link.booking_url("https://zcal.co/i/x?existing=1", name: "Jane") |> query()
      assert params["existing"] == "1"
      assert params["name"] == "Jane"
    end

    test "omits options that are nil or empty" do
      assert Link.booking_url("x", name: nil, email: "", guests: nil, utm: nil) ==
               "https://zcal.co/i/x"
    end
  end

  describe "embed_url/2" do
    test "rewrites a single-segment path to /emb so it can be framed" do
      url = Link.embed_url({:slug, "30min"})

      assert path(url) == "/emb/30min"
      assert Link.framable?(url)
    end

    test "leaves an already-framable /i/<id> path alone" do
      url = Link.embed_url("aZbYc_8")

      assert path(url) == "/i/aZbYc_8"
      assert Link.framable?(url)
    end

    test "applies the rewrite on a custom domain too" do
      assert path(Link.embed_url({:slug, "30min"}, base_url: "https://meet.acme.com")) ==
               "/emb/30min"
    end

    test "adds the widget's embed parameters" do
      params = Link.embed_url({:slug, "30min"}, embed_domain: "capitalwesthomes.com") |> query()

      assert params["embed"] == "1"
      assert params["embedType"] == "inline"
      assert params["embedVersion"] == "1.0.2"
      assert params["embedDomain"] == "capitalwesthomes.com"
    end

    test "omits embedDomain when it is not given and allows overriding embedType" do
      params = Link.embed_url({:slug, "30min"}, embed_type: "popup") |> query()

      refute Map.has_key?(params, "embedDomain")
      assert params["embedType"] == "popup"
    end

    test "carries prefill parameters through" do
      params =
        Link.embed_url({:slug, "30min"}, name: "Jane", utm: [campaign: "spring"]) |> query()

      assert params["name"] == "Jane"
      assert params["utm_campaign"] == "spring"
    end
  end

  describe "framable?/1" do
    test "is true only for the two paths zcal does not send X-Frame-Options: DENY on" do
      assert Link.framable?("https://zcal.co/i/aZbYc_8")
      assert Link.framable?("https://zcal.co/emb/30min")
      assert Link.framable?("https://meet.acme.com/emb/30min")
    end

    test "is false for pretty, team and bare paths" do
      refute Link.framable?("https://zcal.co/jane/30min")
      refute Link.framable?("https://zcal.co/30min")
      refute Link.framable?("https://zcal.co/t/acme/intro")
      refute Link.framable?("https://zcal.co/e/evt_1")
      refute Link.framable?("https://zcal.co/")
    end
  end

  describe "embed_snippet/2" do
    test "renders the official widget markup with the url on the first child anchor" do
      snippet = Link.embed_snippet("aZbYc_8", name: "Jane")

      assert snippet =~ ~s(src="https://static.zcal.co/embed/v1/embed.js")
      assert snippet =~ ~s(<div class="zcal-inline-widget"><a href=")
      assert snippet =~ "https://zcal.co/i/aZbYc_8?name=Jane"
      assert snippet =~ ">Schedule a meeting</a>"
    end

    test "accepts a custom label" do
      assert Link.embed_snippet("x", label: "Book a visit") =~ ">Book a visit</a>"
    end
  end

  describe "default_base_url/0" do
    test "is zcal.co" do
      assert Link.default_base_url() == "https://zcal.co"
    end
  end
end
