defmodule ExZcal.Event do
  @moduledoc """
  A booked zcal event, normalized from a webhook payload.

  This is the shape `ExZcal.Webhook.parse/1` returns. The wire payload nests the
  event under a `"data"` key and puts the person who booked inside
  `"attendees"` (as the entry whose `"type"` is `"invitee"`) rather than at the
  top level — `invitee/1` and friends save you from walking that yourself.

  `type` is the webhook trigger, not a property of the booking: `:created`,
  `:rescheduled`, or `:cancelled`. The full original payload is kept on `raw`
  so nothing this struct omits is lost.
  """

  alias ExZcal.{Answer, Attendee, Host, Invite, Location, Team}

  @utm_keys ~w(campaign source medium content term)a

  defstruct [
    :id,
    :type,
    :webhook_sent_at,
    :starts_at,
    :duration,
    :cancelled,
    :name,
    :invite,
    :location,
    :team,
    hosts: [],
    attendees: [],
    utm: %{},
    raw: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: :created | :rescheduled | :cancelled,
          webhook_sent_at: DateTime.t() | nil,
          starts_at: DateTime.t() | nil,
          duration: pos_integer() | nil,
          cancelled: boolean() | nil,
          name: String.t() | nil,
          invite: Invite.t() | nil,
          location: Location.t() | nil,
          team: Team.t() | nil,
          hosts: [Host.t()],
          attendees: [Attendee.t()],
          utm: %{optional(atom()) => String.t()},
          raw: map()
        }

  @doc false
  @spec new(map(), map(), :created | :rescheduled | :cancelled) :: t()
  def new(%{} = payload, %{} = data, type) do
    %__MODULE__{
      id: data["id"],
      type: type,
      webhook_sent_at: datetime(payload["created_at"]),
      starts_at: datetime(data["startDate"]),
      duration: duration(data["duration"]),
      cancelled: data["cancelled"],
      name: data["eventName"],
      invite: build(Invite, data["invite"]),
      location: build(Location, data["location"]),
      team: build(Team, data["team"]),
      hosts: build_all(Host, data["hosts"]),
      attendees: build_all(Attendee, data["attendees"]),
      utm: utm(payload, data),
      raw: payload
    }
  end

  @doc """
  The attendee who booked — the one whose `type` is `:invitee`.

  Falls back to the first attendee when zcal omits the type, and returns `nil`
  when there are no attendees at all.
  """
  @spec invitee(t()) :: Attendee.t() | nil
  def invitee(%__MODULE__{attendees: attendees}) do
    Enum.find(attendees, &(&1.type == :invitee)) || List.first(attendees)
  end

  @doc "Additional attendees the invitee brought along."
  @spec guests(t()) :: [Attendee.t()]
  def guests(%__MODULE__{attendees: attendees}), do: Enum.filter(attendees, &(&1.type == :guest))

  @doc "The event's first host, or `nil`. Round-robin invites carry exactly one."
  @spec host(t()) :: Host.t() | nil
  def host(%__MODULE__{hosts: hosts}), do: List.first(hosts)

  @doc "The invitee's custom-question answers, in the order zcal sent them."
  @spec answers(t()) :: [Answer.t()]
  def answers(%__MODULE__{} = event) do
    case invitee(event) do
      nil -> []
      invitee -> invitee.answers
    end
  end

  @doc """
  The invitee's answer to `question`, matched case-insensitively and ignoring
  surrounding whitespace, as a display string. Returns `nil` when unanswered.

  Useful for pulling a hidden field you added to the booking form:

      ExZcal.Event.answer(event, "property_id")
  """
  @spec answer(t(), String.t()) :: String.t() | nil
  def answer(%__MODULE__{} = event, question) when is_binary(question) do
    target = normalize_question(question)

    event
    |> answers()
    |> Enum.find(&(normalize_question(&1.question) == target))
    |> case do
      nil -> nil
      found -> Answer.text(found)
    end
  end

  @doc """
  When the event ends, derived from `starts_at` + `duration`. `nil` if either
  is missing.
  """
  @spec ends_at(t()) :: DateTime.t() | nil
  def ends_at(%__MODULE__{starts_at: %DateTime{} = starts_at, duration: duration})
      when is_integer(duration),
      do: DateTime.add(starts_at, duration * 60, :second)

  def ends_at(%__MODULE__{}), do: nil

  @doc "The id of the invite this event was booked through, or `nil`."
  @spec invite_id(t()) :: String.t() | nil
  def invite_id(%__MODULE__{invite: %Invite{id: id}}), do: id
  def invite_id(%__MODULE__{}), do: nil

  # zcal documents that it "forwards UTM parameters to webhooks" but never says
  # where they land in the JSON, and they are absent from its published schema.
  # Look everywhere plausible and return whatever is found; an empty map is a
  # legitimate result.
  defp utm(payload, data) do
    sources = [
      payload,
      data,
      map_at(payload, "utm"),
      map_at(data, "utm"),
      map_at(data, "tracking"),
      map_at(data, "metadata")
    ]

    for key <- @utm_keys,
        value = first_value(sources, "utm_#{key}"),
        into: %{},
        do: {key, value}
  end

  defp first_value(sources, key) do
    Enum.find_value(sources, fn source ->
      case source[key] do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp map_at(source, key) do
    case source[key] do
      %{} = nested -> nested
      _ -> %{}
    end
  end

  defp build(_module, nil), do: nil
  defp build(module, %{} = raw), do: module.new(raw)
  defp build(_module, _other), do: nil

  defp build_all(module, list) when is_list(list) do
    for %{} = raw <- list, do: module.new(raw)
  end

  defp build_all(_module, _other), do: []

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp datetime(_value), do: nil

  defp duration(value) when is_integer(value), do: value

  defp duration(value) when is_binary(value) do
    case Integer.parse(value) do
      {duration, _rest} -> duration
      :error -> nil
    end
  end

  defp duration(_value), do: nil

  defp normalize_question(question),
    do: question |> to_string() |> String.trim() |> String.downcase()
end
