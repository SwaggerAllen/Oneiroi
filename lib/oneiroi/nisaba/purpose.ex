defmodule Oneiroi.Nisaba.Purpose do
  @moduledoc """
  The purposes a call is billed under (spec §6.11), a closed list kept
  in a leaf so the boundary and its service read it without the one
  depending on the other: `mix xref graph --format cycles` counts
  runtime edges, and the first version put the list on the boundary.

  The last two are hidden from the resident's own view: a resident that
  could see drafting or regression spend could see what the unawareness
  invariant hides (spec §6.4).
  """

  # `oracle`: the resident's own long reads (brain#49), on her pinned
  # model, hers to see and budget. `planning`: the turn that closes a
  # free-time slot (sunna#31, #32), its own line so a spent free-time line
  # never refuses it and its cost is never folded in. `work`: the work
  # queue's runs (sunna#33), a line the witness sets, or the loop holds.
  # `rounds`: the thinking rounds (sunna#39), off the free-time line.
  @all ~w(chat free_time planning work rounds judge hands embeddings oracle drafting regression)a
  @witness_only ~w(drafting regression)a

  @type t ::
          :chat
          | :free_time
          | :planning
          | :work
          | :rounds
          | :judge
          | :hands
          | :embeddings
          | :oracle
          | :drafting
          | :regression

  @doc "Every purpose, in the order the screen lists them."
  @spec all() :: [t()]
  def all, do: @all

  @doc "The purposes the resident's own view never shows."
  @spec witness_only() :: [t()]
  def witness_only, do: @witness_only

  @doc "The purposes a view may see."
  @spec visible(:witness | :resident) :: [t()]
  def visible(:witness), do: @all
  def visible(:resident), do: @all -- @witness_only

  @doc "A purpose from its wire string, or nil."
  @spec parse(term()) :: t() | nil
  def parse(string) when is_binary(string), do: Enum.find(@all, &(Atom.to_string(&1) == string))
  def parse(atom) when atom in @all, do: atom
  def parse(_other), do: nil
end
