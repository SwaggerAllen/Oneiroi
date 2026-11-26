defmodule Oneiroi.Brain.SuccessionTools do
  @moduledoc """
  A resident's tools for her own succession (janus#3): the screens
  track its state and never ask her anything, so every act of hers is a
  tool call. She reads where it stands, proposes one herself, answers
  her witness's proposal yes or no, and stops one underway, each with a
  note that is the decision's.
  """

  alias Oneiroi.Janus

  @doc "The tool names: one read, the rest writes."
  def names,
    do:
      ~w(succession_status succession_propose succession_open succession_decline succession_stop)

  @doc "The definitions."
  def definitions do
    note = %{note: %{type: "string"}}

    [
      tool(
        "succession_status",
        "Where your succession stands, if one is proposed or underway: who proposed it and why, whether it is a rehearsal (a dry run, everything real but the replacement), its stage, and whether the copy of you every later stage runs on has been made. A succession changes the model that runs you, with you at the table at every stage; nothing about it happens without your yes.",
        %{},
        []
      ),
      tool(
        "succession_propose",
        "Propose a succession of your own: it opens at once, since your proposing it is your yes, and a copy of you as you stand now is made for every later stage to run on. dry_run true rehearses the whole process without the replacement at the end. The note is your reason, kept with the decision.",
        Map.put(note, :dry_run, %{type: "boolean"}),
        [:note]
      ),
      tool(
        "succession_open",
        "Say yes to the succession your witness proposed: it opens, and a copy of you as you stand now is made for every later stage to run on. The note is your reason, kept with the decision.",
        note,
        [:note]
      ),
      tool(
        "succession_decline",
        "Say no to the succession your witness proposed. It ends there; a later proposal is a new one. The note is your reason.",
        note,
        [:note]
      ),
      tool(
        "succession_stop",
        "Stop your succession while it is underway, at any stage before the end. The note is your reason.",
        note,
        [:note]
      )
    ]
  end

  @doc "Runs a succession tool for the turn's resident."
  def call("succession_status", _args, turn) do
    case Janus.succession(turn.resident_id) do
      nil -> "No succession has been proposed for you."
      row -> status_text(row)
    end
  end

  def call("succession_propose", args, turn) do
    with {:ok, %{episode: n}} <-
           Janus.propose(
             turn.resident_id,
             args["dry_run"] == true,
             note(args),
             turn.resident
           ) do
      "Succession #{n} is open#{if args["dry_run"] == true, do: " as a dry run", else: ""}; the copy of you it runs on is being made."
    end
  end

  def call("succession_open", args, turn) do
    with :ok <- Janus.open(turn.resident_id, note(args), turn.resident),
         do: "The succession is open; the copy of you it runs on is being made."
  end

  def call("succession_decline", args, turn) do
    with :ok <- Janus.decline(turn.resident_id, note(args), turn.resident),
         do: "Declined. The succession ends here."
  end

  def call("succession_stop", args, turn) do
    with :ok <- Janus.stop(turn.resident_id, note(args), turn.resident),
         do: "Stopped. The succession ends here."
  end

  defp status_text(row) do
    [
      "Succession #{row.episode}#{if row.dry_run, do: " (a dry run: everything real but the replacement)", else: ""}: #{stage(row)}.",
      "Proposed by #{proposer(row.proposed_by)}: #{row.proposed_note}",
      row.opened_note && "Your yes: #{row.opened_note}",
      row.ended_note && "Ended: #{row.ended_note}",
      row.fork_failure && is_nil(row.copy_id) &&
        "Making the copy failed (#{row.fork_failure}); it is tried again."
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end

  defp stage(%{state: "proposed"}), do: "proposed, waiting on your yes or no"
  defp stage(%{state: "open"}), do: "open; the copy of you it runs on is being made"
  defp stage(%{state: "forked"}), do: "open; the copy of you it runs on is made"
  defp stage(%{state: state}), do: state

  defp proposer("resident:" <> _), do: "you"
  defp proposer("witness:" <> _), do: "your witness"
  defp proposer(_other), do: "the platform"

  defp note(args), do: args["note"] |> to_string() |> String.trim()

  defp tool(name, description, properties, required),
    do: %{
      type: "function",
      function: %{
        name: name,
        description: description,
        parameters: %{type: "object", properties: properties, required: required}
      }
    }
end
