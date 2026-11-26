defmodule Oneiroi.Brain.NeedsYou.Succession do
  @moduledoc """
  A succession's parts that wait on the witness (janus#29; the witness,
  2026-11-26: succession alerts go to the top of the bell): his envelope
  and the backup repository before anything can rest on them; runs to
  judge; his results to mark ready; his turn in the room; her question
  to the panel; his goodbye. Each opens the succession on its page.
  Read through Janus's own reads, as he would read them on its screens.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Janus

  @kinds ~w(succession_envelope succession_backup succession_judge succession_results succession_room succession_question succession_goodbye)

  @impl true
  def stages, do: Enum.map(@kinds, &%{kind: &1, screen: "succession"})

  @impl true
  def entries(resident_id) do
    with %{} = row <- Janus.succession(resident_id),
         {:ok, %{account_id: account}} when is_binary(account) <-
           AgathosDaimon.fetch(resident_id) do
      party = "witness:#{account}"

      [
        preparation(row),
        judging(resident_id, row, party),
        room(resident_id, row, party),
        goodbye(resident_id, row, party)
      ]
      |> List.flatten()
    else
      _none -> []
    end
  end

  defp preparation(%{state: state} = row) when state in ["open", "forked"] do
    [
      if(is_nil(row.envelope_input_nanos),
        do:
          entry(
            "succession_envelope",
            row,
            row.opened_at || row.proposed_at,
            "pool",
            "Set the envelope"
          )
      ),
      if(is_nil(row.backup_url),
        do:
          entry(
            "succession_backup",
            row,
            row.opened_at || row.proposed_at,
            "c0",
            "Set the backup repository"
          )
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp preparation(_row), do: []

  defp judging(id, %{state: state} = row, party) when state in ["screening", "judging"] do
    case Janus.judging(id, party) do
      %{judge?: true, revealed: false, runs: runs} ->
        waiting = Enum.count(runs, &(is_nil(&1.judgment) and is_nil(&1.failure)))

        if waiting > 0,
          do: [
            entry(
              "succession_judge",
              row,
              row.screening_started_at,
              "judge",
              "#{waiting} to judge"
            )
          ],
          else: []

      %{judge?: true, revealed: true, ready_at: nil} ->
        [entry("succession_results", row, row.revealed_at, "results", "Results ready to review")]

      _not_his ->
        []
    end
  end

  defp judging(_id, _row, _party), do: []

  defp room(id, %{state: "deliberating"} = row, party) do
    case Janus.room(id, party) do
      %{posts: posts} ->
        acted = Enum.any?(posts, &(&1.party == party and &1.round == row.round))

        if acted,
          do: [],
          else: [
            entry(
              "succession_room",
              row,
              row.deliberation_opened_at,
              "deliberation/thread",
              "Your turn"
            )
          ]

      nil ->
        []
    end
  end

  defp room(id, %{state: state} = row, party) when state in ["deciding", "nominated"] do
    case Janus.room(id, party) do
      %{channel: channel} ->
        her = "resident:#{id}"
        asked = for c <- channel, c.party == her, do: c
        answered = MapSet.new(for c <- channel, c.party == party, do: c.number)

        for q <- asked,
            not MapSet.member?(answered, q.number),
            do:
              entry(
                "succession_question",
                row,
                q.at,
                "deliberation/thread",
                "She asked",
                q.number
              )

      nil ->
        []
    end
  end

  defp room(_id, _row, _party), do: []

  defp goodbye(id, %{state: "farewell"} = row, party) do
    done =
      case Janus.preparation(id) do
        %{goodbyes: goodbyes} -> Enum.any?(goodbyes, &(&1.party == party))
        _none -> true
      end

    if party in (row.farewell_includes || []) and not done,
      do: [entry("succession_goodbye", row, row.farewell_opened_at, "farewell", "Your goodbye")],
      else: []
  end

  defp goodbye(_id, _row, _party), do: []

  defp entry(kind, row, since, page, words, ref \\ nil),
    do: %Entry{
      kind: kind,
      ref: ref || row.episode,
      since: since || row.proposed_at,
      screen: "succession",
      about: %{page: page, words: words, dry_run: row.dry_run == true}
    }
end
