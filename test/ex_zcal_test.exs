defmodule ExZcalTest do
  use ExUnit.Case, async: true

  alias ExZcal.Fixtures

  doctest ExZcal

  test "delegates webhook verification and parsing" do
    body = Fixtures.raw_payload()

    assert ExZcal.verify(body, Fixtures.sign(body, Fixtures.secret()), Fixtures.secret()) == :ok
    assert {:ok, event} = ExZcal.parse(Fixtures.payload())
    assert event.id == "sample-event-id"
    assert ExZcal.signature_header() == "x-zcal-webhook-signature"
  end

  test "delegates link building" do
    assert ExZcal.booking_url("aZbYc_8") == "https://zcal.co/i/aZbYc_8"
    assert ExZcal.embed_url({:slug, "30min"}) =~ "/emb/30min"
    assert ExZcal.embed_snippet("aZbYc_8") =~ "zcal-inline-widget"
    assert ExZcal.framable?("https://zcal.co/i/aZbYc_8")
  end
end
