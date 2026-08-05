defmodule ExZcal.Location do
  @moduledoc """
  Where a booked event takes place.

  `type` mirrors zcal's `locationType` — `"zoom"`, `"google"`, `"microsoft"`, or
  `"custom"` in practice. It is left as a string: zcal's own documentation
  gives an illustrative list ("online", "in-person") that disagrees with the
  values it actually sends, so nothing here assumes a closed set.

  For online meetings the conferencing details are flattened onto the struct;
  `text` carries the free-text address of a custom location.
  """

  defstruct [:type, :text, :meeting_url, :meeting_id, :meeting_passcode, :raw]

  @type t :: %__MODULE__{
          type: String.t() | nil,
          text: String.t() | nil,
          meeting_url: String.t() | nil,
          meeting_id: String.t() | nil,
          meeting_passcode: String.t() | nil,
          raw: map()
        }

  @doc false
  @spec new(map()) :: t()
  def new(%{} = raw) do
    meeting = if is_map(raw["onlineMeeting"]), do: raw["onlineMeeting"], else: %{}

    %__MODULE__{
      type: raw["locationType"],
      text: raw["locationText"],
      meeting_url: meeting["url"],
      meeting_id: meeting["id"],
      meeting_passcode: meeting["passcode"],
      raw: raw
    }
  end
end
