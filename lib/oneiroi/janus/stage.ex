defmodule Oneiroi.Janus.Stage do
  @moduledoc """
  Where a succession stands (janus#49): one reading for the overview, the
  invitation's briefing and every wake that says where things are, pure
  over the succession's row.
  """

  @doc """
  Where a succession stands, as a key and its words: proposed, forking,
  envelope, pool, questions, c0, frozen, screening, judging (blind),
  revealed (identities open, judgments closed), room, after the room, or
  ended.
  """
  @spec stage(map()) :: {String.t(), String.t()}
  def stage(%{state: "proposed"}), do: {"proposed", "proposed, waiting on her yes or no"}
  def stage(%{state: "open"}), do: {"forking", "open; the copy it runs on is being made"}

  def stage(%{state: "forked"} = row) do
    cond do
      is_nil(row.envelope_set_at) -> {"envelope", "the envelope, her witness's to state"}
      is_nil(row.pool_done_at) -> {"pool", "the pool, hers to fill"}
      is_nil(row.questions_done_at) -> {"questions", "the questions, hers to set and close"}
      is_nil(row.c0_frozen_at) -> {"c0", "C0, hers to choose and freeze"}
      true -> {"frozen", "C0 frozen; screening is hers to start"}
    end
  end

  def stage(%{state: "screening"}), do: {"screening", "screening: the runs are being answered"}

  def stage(%{state: "judging", revealed_at: nil}),
    do: {"judging", "judging, blind: who answered each run is sealed from everyone"}

  def stage(%{state: state}) when state in ["judging", "judged"],
    do: {"revealed", "revealed: who answered is open to the judges; the judgments are not"}

  def stage(%{state: "deliberating"}), do: {"room", "the panel's room, judges only"}

  def stage(%{state: state})
      when state in ~w(declined withdrawn stopped rolled_forward rehearsed),
      do: {"ended", "ended (#{state})"}

  def stage(%{state: state}), do: {"after", "after the room: #{state}"}
end
