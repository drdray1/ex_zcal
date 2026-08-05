defmodule ExZcal.Answer do
  @moduledoc """
  A booker's answer to one of an invite's custom questions.

  zcal sends `answer` as a **string** for free-text, dropdown, and radio
  questions but as a **list of strings** for checkbox questions. `values` is
  always normalized to a list so callers never have to branch on the type;
  `text/1` joins it back into one display string.
  """

  defstruct [:question, :values, :raw]

  @type t :: %__MODULE__{
          question: String.t(),
          values: [String.t()],
          raw: map()
        }

  @doc false
  @spec new(map()) :: t()
  def new(%{} = raw) do
    %__MODULE__{
      question: stringify(raw["question"] || raw["label"] || ""),
      values: values(raw["answer"] || raw["value"]),
      raw: raw
    }
  end

  @doc """
  The answer as a single display string. Checkbox answers (multiple values) are
  joined with `", "`; an unanswered question yields `""`.
  """
  @spec text(t()) :: String.t()
  def text(%__MODULE__{values: values}), do: Enum.join(values, ", ")

  defp values(nil), do: []
  defp values(value) when is_list(value), do: Enum.map(value, &stringify/1)
  defp values(value), do: [stringify(value)]

  # Never raises on an unexpected shape — the payload is unversioned.
  defp stringify(value) when is_binary(value), do: value

  defp stringify(value) when is_number(value) or is_boolean(value) or is_atom(value),
    do: to_string(value)

  defp stringify(value), do: inspect(value)
end
