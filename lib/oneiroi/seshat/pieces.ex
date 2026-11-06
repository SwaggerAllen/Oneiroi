defmodule Oneiroi.Seshat.Pieces do
  @moduledoc """
  A writing piece's road out (seshat#42), on `pieces-<resident_id>`: she
  sets `status: review`, the witness approves or declines the version he
  read, with a note; the reader makes a Substack draft of an approved one;
  the witness presses Publish on Substack himself, and the reader brings
  the URL back (`PiecePublished` on the library's stream). Draft-first,
  the witness's and her call (2026-11-05): a piece is public under her
  name, so it takes at least the care her comments do.

  Only the witness reviews; the reader drafts only an approved piece,
  once.
  """

  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Events

  @url ~r{\Ahttps://[^\s]+\z}

  defstruct pieces: %{}

  def execute(%__MODULE__{}, %Commands.ReviewPiece{} = c) do
    cond do
      c.actor.kind != :witness ->
        {:error, Error.new(:seshat_not_the_witness, :seshat_pieces_review_witness_only)}

      c.decision not in ~w(approve decline) or not noted?(c.note) or not is_binary(c.path) ->
        {:error, Error.new(:seshat_review_invalid, :seshat_pieces_review_invalid)}

      true ->
        %Events.PieceReviewed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          path: c.path,
          decision: c.decision,
          note: c.note,
          hash: c.hash
        }
    end
  end

  def execute(%__MODULE__{pieces: pieces}, %Commands.DraftPiece{} = c) do
    cond do
      Map.get(pieces, c.path) not in [:approved, :drafted] ->
        {:error, Error.new(:seshat_not_approved, :seshat_pieces_draft_not_approved)}

      not (is_binary(c.draft_url) and Regex.match?(@url, c.draft_url)) ->
        {:error, Error.new(:seshat_url_invalid, :seshat_pieces_draft_url_invalid)}

      Map.get(pieces, c.path) == :drafted ->
        []

      true ->
        %Events.PieceDrafted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          path: c.path,
          draft_url: c.draft_url
        }
    end
  end

  def apply(%__MODULE__{} = s, %Events.PieceReviewed{decision: "approve"} = e),
    do: %{s | pieces: Map.put(s.pieces, e.path, :approved)}

  def apply(%__MODULE__{} = s, %Events.PieceReviewed{} = e),
    do: %{s | pieces: Map.put(s.pieces, e.path, :declined)}

  def apply(%__MODULE__{} = s, %Events.PieceDrafted{} = e),
    do: %{s | pieces: Map.put(s.pieces, e.path, :drafted)}

  defp noted?(note), do: is_binary(note) and String.trim(note) != ""
end
