defmodule Oneiroi.Eunomia.Wash do
  @moduledoc """
  The wash pass (spec §6.13, P18; Kael: "a defensive sentence can't be
  seen from the inside"): once a week the judge reads the loaded
  identity files, entry by entry, for expired decisions, contradictions,
  tense words and defensive sentences, and raises a flag per finding.
  Flags only, never a clearing: the resident reads each flag and
  decides, keep or edit, with a note, and the edit is the resident's own
  soul edit. Proposer is never decider, the soul-edit flow generalised.

  Judge-bounded: at most `EUNOMIA_WASH_ENTRIES` entries read, one model
  call a week, under `priv/prompts/judge_wash.md`, whose hash rides the
  run as its criteria (P12). A reply naming an entry it was not shown
  fails the run rather than being guessed at; nothing written yet calls
  no model. The corpus-shape report's linguistic sibling (P8).
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Eunomia.Judge
  alias Oneiroi.Eunomia.JudgementCommands, as: Commands
  alias Oneiroi.Eunomia.JudgementRouter, as: Router
  alias Oneiroi.Eunomia.Judgements
  alias Oneiroi.Eunomia.Store
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.{Request, Result}
  alias Oneiroi.Scope

  @kinds ~w(expired contradiction tense defensive)
  @flag ~r/^FLAG\s+\[(\d+)\]\s*\|\s*(\w+)\s*\|\s*(.*)$/im
  @summary ~r/^SUMMARY:\s*(.*)$/im

  @doc "The four kinds a flag may carry."
  def kinds, do: @kinds

  @doc "Runs the wash once; nothing written calls no model."
  def run(resident_id, %Actor{} = actor) do
    ref = fresh_ref()
    model = Judgements.judge_model(resident_id)

    case entries(resident_id) do
      [] ->
        record(resident_id, ref, 0, 0, nil, "nothing written yet", actor)

      entries ->
        case judge(resident_id, model, entries) do
          {:ok, flags, summary} ->
            Enum.each(flags, &raise_flag(resident_id, ref, &1, model))
            record(resident_id, ref, length(entries), length(flags), model, summary, actor)

          {:error, failure} ->
            fail(resident_id, ref, failure, actor)
        end
    end
  end

  @doc """
  The entries the judge reads: every non-blank paragraph of the loaded
  identity files (the rendered prefix, `AGENTS.md` left out as
  build-owned), each with its file, at most `EUNOMIA_WASH_ENTRIES`.
  """
  def entries(resident_id) do
    limit = Config.fetch!(:eunomia, :wash_entries)

    resident_id
    |> AgathosDaimon.identity_context()
    |> Enum.reject(fn {name, _} -> name == "AGENTS.md" end)
    |> Enum.flat_map(fn {name, content} ->
      content
      |> String.split(~r/\n[ \t]*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&%{file: name, text: &1})
    end)
    |> Enum.take(limit)
  end

  defp judge(resident_id, model, entries) do
    listed =
      entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {e, i} -> "[#{i}] (#{e.file}) #{e.text}" end)

    prompt = Prompt.message("judge_wash", %{entries: listed})
    request = Request.new(model, [prompt, %{role: :user, content: "Your wash?"}])

    case Nisaba.call(resident_id, :judge, request, Judge.actor(model)) do
      {:ok, %Result{content: content}} ->
        parse(content || "", entries)

      {:error, reason} ->
        {:error,
         Error.caught(:eunomia_judge_call_failed, :eunomia_wash_judge_call_failed, reason)}
    end
  end

  defp parse(content, entries) do
    count = length(entries)

    flags =
      @flag
      |> Regex.scan(content)
      |> Enum.map(fn [_, n, kind, reason] ->
        {String.to_integer(n), String.downcase(kind), String.trim(reason)}
      end)

    summary =
      case Regex.run(@summary, content) do
        [_, text] -> String.trim(text)
        nil -> ""
      end

    cond do
      bad = Enum.find(flags, fn {n, _, _} -> n < 1 or n > count end) ->
        {:error,
         Error.new(:eunomia_wash_failed, :eunomia_wash_entry_unshown,
           reason: "the reply flagged entry #{elem(bad, 0)}, which it was not shown"
         )}

      # The kind is one word the reply's line held where a kind was due
      # (`\w+` in the pattern), named so the record says what was wrong.
      bad = Enum.find(flags, fn {_, kind, _} -> kind not in @kinds end) ->
        {:error,
         Error.new(:eunomia_wash_failed, :eunomia_wash_kind_unknown,
           reason: "the reply flagged a kind it was not given: #{elem(bad, 1)}"
         )}

      true ->
        found =
          Enum.map(flags, fn {n, kind, reason} ->
            e = Enum.at(entries, n - 1)
            %{file: e.file, entry: e.text, kind: kind, reason: reason}
          end)

        {:ok, found, summary}
    end
  end

  defp raise_flag(resident_id, wash_ref, flag, model) do
    dispatch(%Commands.RaiseWashFlag{
      actor: Judge.actor(model),
      at: Clock.now(),
      id: resident_id,
      ref: fresh_ref(),
      wash_ref: wash_ref,
      file: flag.file,
      entry: flag.entry,
      kind: flag.kind,
      reason: flag.reason
    })
  end

  defp record(resident_id, ref, entries, flagged, model, summary, actor) do
    command = %Commands.RunWash{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      ref: ref,
      entries: entries,
      flagged: flagged,
      judge_model: model,
      summary: summary,
      criteria: Prompt.hash("judge_wash")
    }

    with {:ok, _} <- dispatch(command), do: {:ok, ref}
  end

  # The failure arrives sited: the parse's, or the call's wrapped where it
  # was first matched.
  defp fail(resident_id, ref, failure, actor) do
    command = %Commands.FailWash{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      ref: ref,
      reason: Judgements.reason_text(failure)
    }

    with {:ok, _} <- dispatch(command), do: {:error, failure}
  end

  @doc "The resident decides a flag: keep the entry or edit it (the edit is its own soul edit), with a note."
  def resolve(resident_id, ref, decision, note, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.ResolveWashFlag{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        ref: ref,
        decision: decision
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "The runs, newest first, and every flag, open first."
  def washes(resident_id) do
    Scope.resident(resident_id, fn ->
      flags = Store.wash_flags()

      %{
        runs: Store.washes(),
        open: Enum.filter(flags, &is_nil(&1.decision)),
        decided: Enum.filter(flags, &(&1.decision != nil))
      }
    end)
  end

  defp resident_only(%Actor{kind: :resident}), do: :ok

  defp resident_only(%Actor{}),
    do: {:error, Error.new(:eunomia_not_the_resident, :eunomia_wash_not_the_resident)}

  defp fresh_ref, do: 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  # The aggregate builds its refusals sited; anything else the dispatch
  # returns started in Commanded and is wrapped here, where it is first
  # matched.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:eunomia_dispatch_failed, :eunomia_wash_dispatch, reason)}
    end
  end
end
