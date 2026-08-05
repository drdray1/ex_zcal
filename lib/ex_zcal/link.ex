defmodule ExZcal.Link do
  @moduledoc """
  Building booking-page URLs: prefilled links, embeddable URLs, and the embed
  snippet.

  ## Referencing an invite

  Every function takes an `invite_ref`, which may be:

    * `{:invite, "aZbYc_8"}` — an invite id, addressed as `/i/aZbYc_8`
    * `{:slug, "30min"}` — a pretty slug, addressed as `/30min`
    * a bare string — treated as an **invite id**, so `"aZbYc_8"` is the same as
      `{:invite, "aZbYc_8"}`
    * a path with a slash — `"i/aZbYc_8"`, `"jane/30min"`, `"t/acme/intro"`,
      used as given
    * a full URL — `"https://meet.acme.com/30min"`, used as-is (so custom
      domains work without extra configuration)

  A bare string means an invite id rather than a slug because the two are
  indistinguishable and only one of them is safe: `/i/<id>` is framable and
  survives renaming the pretty slug. Reach for `{:slug, _}` when you do mean a
  slug.

  ## Framing

  This matters more than it looks. zcal serves `X-Frame-Options: DENY` on
  **every** booking path except `/i/<id>` and `/emb/<slug>`, so dropping a
  normal booking link into an `<iframe>` renders a blank box. `embed_url/2`
  applies the same rewrite zcal's own widget does — a single-segment path such
  as `/30min` becomes `/emb/30min` — and `framable?/1` will tell you whether a
  URL can be framed at all:

      ExZcal.Link.embed_url("30min")   #=> "https://zcal.co/emb/30min?embed=1&..."
      ExZcal.Link.framable?("https://zcal.co/jane/30min")  #=> false

  ## Prefilling

  Custom-question answers are positional — `a0`, `a1`, … in the order the
  questions appear on the invite. Dropdown and checkbox answers must match the
  configured options exactly; zcal silently ignores parameters it cannot use.
  """

  @default_base_url "https://zcal.co"
  @embed_script "https://static.zcal.co/embed/v1/embed.js"
  @embed_version "1.0.2"
  @utm_keys ~w(campaign source medium content term)a

  @typedoc """
  How to address an invite: an id, a slug, a path, or a full URL. A bare string
  is an invite id.
  """
  @type invite_ref :: String.t() | {:invite, String.t()} | {:slug, String.t()}

  @doc """
  A booking-page URL with any prefill parameters applied.

  Options:

    * `:base_url` — defaults to `#{@default_base_url}`; set it for a custom domain.
    * `:name`, `:email` — prefill the booker's details.
    * `:start_date` — a `DateTime` or ISO-8601 string to preselect a slot.
    * `:timezone` — an IANA name, e.g. `"America/Phoenix"`.
    * `:guests` — a list of email addresses (or a comma-joined string).
    * `:duration` — preselect a duration **by value in minutes**, not by index.
    * `:location_index` — 0-based index into the invite's location options.
    * `:sms_phone` — reminder phone number; must include a country code.
    * `:answers` — custom-question answers, either a list in question order or a
      map of `%{index => answer}`. A list value becomes a comma-joined checkbox
      answer.
    * `:utm` — `[campaign: "spring", content: "sidebar"]`, sent as `utm_*`.
    * `:params` — any extra query params, merged last.

  ## Examples

      ExZcal.Link.booking_url("aZbYc_8", name: "Jane", email: "jane@example.com")
      #=> "https://zcal.co/i/aZbYc_8?email=jane%40example.com&name=Jane"

      ExZcal.Link.booking_url("aZbYc_8", answers: ["Blue", ["Option 1", "Option 3"]])
      #=> "https://zcal.co/i/aZbYc_8?a0=Blue&a1=Option+1%2COption+3"
  """
  @spec booking_url(invite_ref(), keyword()) :: String.t()
  def booking_url(invite_ref, opts \\ []) do
    invite_ref
    |> to_uri(opts)
    |> merge_query(prefill_params(opts))
    |> URI.to_string()
  end

  @doc """
  An embeddable booking URL — `booking_url/2` plus the rewrite and query
  parameters zcal's widget applies, so the result can actually be framed.

  Takes every `booking_url/2` option plus:

    * `:embed_domain` — the host of the page doing the embedding, which zcal
      uses to scope the embed.
    * `:embed_type` — defaults to `"inline"`.

  A single-segment path is rewritten to `/emb/<slug>`; `/i/<id>` is left alone
  because it is already framable.
  """
  @spec embed_url(invite_ref(), keyword()) :: String.t()
  def embed_url(invite_ref, opts \\ []) do
    embed_params =
      [
        {"embed", "1"},
        {"embedType", Keyword.get(opts, :embed_type, "inline")},
        {"embedVersion", @embed_version}
      ] ++ embed_domain_param(opts[:embed_domain])

    invite_ref
    |> to_uri(opts)
    |> embeddable_path()
    |> merge_query(prefill_params(opts) ++ embed_params)
    |> URI.to_string()
  end

  @doc """
  The official JS-widget markup for an invite.

  Preferred over a hand-rolled `<iframe>`: the widget auto-resizes to the
  booking page's height, which a plain iframe cannot do. Accepts the same
  options as `booking_url/2`, plus `:label` for the anchor text (shown before
  the script upgrades it).

  Note the structure is load-bearing — the widget reads the URL from the
  anchor that is the *first child* of the `zcal-inline-widget` element.
  """
  @spec embed_snippet(invite_ref(), keyword()) :: String.t()
  def embed_snippet(invite_ref, opts \\ []) do
    url = booking_url(invite_ref, opts)
    label = Keyword.get(opts, :label, "Schedule a meeting")

    """
    <script type="text/javascript" async src="#{@embed_script}"></script>
    <div class="zcal-inline-widget"><a href="#{url}">#{label}</a></div>\
    """
  end

  @doc """
  Whether a URL can be embedded in an `<iframe>`.

  True only for `/i/<id>` and `/emb/<slug>`; everything else is served with
  `X-Frame-Options: DENY`.
  """
  @spec framable?(String.t()) :: boolean()
  def framable?(url) when is_binary(url) do
    case url |> URI.parse() |> path_segments() do
      ["i", _id | _rest] -> true
      ["emb" | _rest] -> true
      _segments -> false
    end
  end

  @doc "The default zcal base URL."
  @spec default_base_url() :: String.t()
  def default_base_url, do: @default_base_url

  # --- URL construction -------------------------------------------------------

  defp to_uri("http://" <> _rest = url, _opts), do: URI.parse(url)
  defp to_uri("https://" <> _rest = url, _opts), do: URI.parse(url)

  defp to_uri({:invite, id}, opts), do: path_uri("i/" <> String.trim(id, "/"), opts)
  defp to_uri({:slug, slug}, opts), do: path_uri(String.trim(slug, "/"), opts)

  defp to_uri(ref, opts) when is_binary(ref) do
    path = String.trim(ref, "/")

    # A bare string with no slash is an invite id; anything else is a path.
    if String.contains?(path, "/"),
      do: path_uri(path, opts),
      else: to_uri({:invite, path}, opts)
  end

  defp path_uri(path, opts) do
    base = opts |> Keyword.get(:base_url, @default_base_url) |> URI.parse()

    %{base | path: "/" <> path}
  end

  # zcal's widget prefixes single-segment paths with /emb, which is what makes
  # custom-domain and pretty-slug pages framable.
  defp embeddable_path(%URI{} = uri) do
    case path_segments(uri) do
      [single] -> %{uri | path: "/emb/" <> single}
      _segments -> uri
    end
  end

  defp path_segments(%URI{path: path}) do
    (path || "") |> String.split("/", trim: true)
  end

  defp merge_query(%URI{} = uri, []), do: uri

  defp merge_query(%URI{} = uri, params) do
    existing = if uri.query, do: URI.decode_query(uri.query), else: %{}
    merged = Enum.reduce(params, existing, fn {key, value}, acc -> Map.put(acc, key, value) end)

    %{uri | query: URI.encode_query(merged)}
  end

  # --- Prefill parameters -----------------------------------------------------

  defp prefill_params(opts) do
    [
      {"name", opts[:name]},
      {"email", opts[:email]},
      {"startDate", start_date(opts[:start_date])},
      {"timezone", opts[:timezone]},
      {"guests", join(opts[:guests])},
      {"duration", opts[:duration]},
      {"locationIndex", opts[:location_index]},
      {"smsPhone", opts[:sms_phone]}
    ]
    |> Enum.concat(answer_params(opts[:answers]))
    |> Enum.concat(utm_params(opts[:utm]))
    |> Enum.concat(extra_params(opts[:params]))
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.map(fn {key, value} -> {key, to_string(value)} end)
  end

  defp start_date(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp start_date(value), do: value

  defp answer_params(nil), do: []

  defp answer_params(answers) when is_list(answers) do
    answers
    |> Enum.with_index()
    |> Enum.map(fn {answer, index} -> {"a#{index}", join(answer)} end)
  end

  defp answer_params(answers) when is_map(answers) do
    Enum.map(answers, fn {index, answer} -> {"a#{index}", join(answer)} end)
  end

  defp utm_params(nil), do: []

  defp utm_params(utm) do
    for key <- @utm_keys, value = get(utm, key), do: {"utm_#{key}", value}
  end

  defp extra_params(nil), do: []
  defp extra_params(params), do: Enum.map(params, fn {key, value} -> {to_string(key), value} end)

  # zcal's widget sends the embedding page's host with the protocol, port and
  # path stripped.
  defp embed_domain_param(nil), do: []

  defp embed_domain_param(domain) do
    host =
      domain
      |> to_string()
      |> String.replace(~r{^[a-z]+://}i, "")
      |> String.split("/", parts: 2)
      |> hd()
      |> String.split(":", parts: 2)
      |> hd()

    if host == "", do: [], else: [{"embedDomain", host}]
  end

  defp get(source, key) when is_map(source), do: Map.get(source, key)
  defp get(source, key) when is_list(source), do: Keyword.get(source, key)

  # Checkbox answers and guest lists both go over the wire comma-joined.
  defp join(nil), do: nil
  defp join(values) when is_list(values), do: Enum.map_join(values, ",", &to_string/1)
  defp join(value), do: value
end
