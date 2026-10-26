defmodule Oneiroi.Actor do
  @moduledoc """
  Who did a thing, and on which model (spec §3.1): every command carries
  one and every event records it. `kind` is the closed vocabulary of
  parties the platform knows; `id` is the party's own id where it has one
  (an account, a resident, a job); `model` is the slug of the model that
  produced the content, where a model did.

  A struct rather than a loose map so the command edge can refuse a
  command without one (`Oneiroi.Commanded.Middleware.Actor`) and the
  serializer can restore it from the log (`Oneiroi.Event`).
  """

  @kinds [:steward, :resident, :judge, :hands, :job, :platform]

  @enforce_keys [:kind]
  @derive Jason.Encoder
  defstruct [:kind, :id, :model]

  @type kind :: :steward | :resident | :judge | :hands | :job | :platform
  @type t :: %__MODULE__{kind: kind(), id: String.t() | nil, model: String.t() | nil}

  @doc "The parties the platform knows."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "Builds an actor, or raises on a kind the platform does not know."
  @spec new(kind(), String.t() | nil, String.t() | nil) :: t()
  def new(kind, id \\ nil, model \\ nil) when kind in @kinds do
    %__MODULE__{kind: kind, id: id, model: model}
  end

  @doc "The platform itself, acting on its own behalf (a job, a migration)."
  @spec platform() :: t()
  def platform, do: %__MODULE__{kind: :platform}

  @doc "Whether a term is a well-formed actor."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{kind: kind, id: id, model: model}) when kind in @kinds do
    (is_nil(id) or is_binary(id)) and (is_nil(model) or is_binary(model))
  end

  def valid?(_other), do: false

  @doc "Restores an actor from its decoded JSON form; `nil` for anything else."
  @spec from_map(term()) :: t() | nil
  def from_map(%{"kind" => kind} = map) when is_binary(kind) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == kind)) do
      nil -> nil
      found -> %__MODULE__{kind: found, id: map["id"], model: map["model"]}
    end
  end

  # Commanded's deserializer atomizes keys before the decoder runs; the
  # export's reader hands string keys. Both are one actor.
  def from_map(%{kind: kind} = map) when is_atom(kind) and kind in @kinds do
    %__MODULE__{kind: kind, id: map[:id], model: map[:model]}
  end

  def from_map(%{kind: kind} = map) when is_binary(kind) do
    from_map(%{"kind" => kind, "id" => map[:id], "model" => map[:model]})
  end

  def from_map(%__MODULE__{} = actor), do: actor
  def from_map(_other), do: nil
end
