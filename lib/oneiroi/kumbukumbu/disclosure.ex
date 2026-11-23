defmodule Oneiroi.Kumbukumbu.Disclosure do
  @moduledoc """
  The review a held-back delivery is owed (kumbukumbu#82; the house
  thread's design, the witness's ruling #7, Lily's letter #1514). The
  ledger's union check is the tripwire: it says *when* a review is owed,
  because something the audience may not hear was in the turn's context.
  The judge says *whether* the candidate discloses it.

  **What is reviewable.** Inputs held back because no policy allows the
  audience, because their domain has none, or because they are
  unclassified. An explicit deny, or an audience not resolved, is refused
  as before, unreviewed: the judge may refuse, never grant past a deny.

  **What the judge sees.** The exact candidate and what tripped the
  review, never the discussion around it (kumbukumbu#105,
  `Ledger.fragments/3`: a message as itself, a bookmark its line and
  summary, the lanes' bookmarks in a domain). An input whose words
  cannot be found leaves the ledger unproven, and the delivery fails
  closed.

  **The judge** is her configured judge model, Eunomia's (the witness's
  ruling, 2026-11-20), through the port `KUMBUKUMBU_DISCLOSURE_JUDGE`
  names; `none` is a deployment with no judge.

  **Fail closed.** No judge, a call that fails, times out
  (`KUMBUKUMBU_DISCLOSURE_JUDGE_MS`) or answers out of form, a verdict
  that it discloses: nothing ships, and she is told in her own context.

  **The record.** Every verdict the judge gives or fails to give is a
  `DisclosureJudged` decision on her conversation's stream: the decision
  id, the policy version, the audience, the verdict and its reasons, the
  candidate's SHA-256, the fragments' refs and the model. Never the
  restricted words; her repository's reading copy shows it, the house
  nothing.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Conversations
  alias Oneiroi.Kumbukumbu.Error

  @reviewable [:not_allowed, :no_policy, :unclassified]

  @doc """
  Reviews `candidate` for delivery to `audience`, held back by
  `decision`: `{:ok, decision}` on a clean verdict, the refusal
  otherwise. `refused` is the refusal's details, the ledger's; `shown`
  finds the held-back inputs' words (`Ledger.fragments/3`).
  """
  def review(turn, audience, candidate, decision, inputs, refused, shown) do
    held = MapSet.new(decision.withheld, & &1.id)

    cond do
      # Nobody to decide against: never reviewed (kumbukumbu#84).
      Enum.any?(decision.withheld, &(&1.reason == :unresolved_audience)) ->
        {:error,
         Error.new(:kumbukumbu_withheld_by_policy, :kumbukumbu_disclosure_unresolved, refused)}

      not Enum.all?(decision.withheld, &(&1.reason in @reviewable)) ->
        {:error,
         Error.new(:kumbukumbu_withheld_by_policy, :kumbukumbu_disclosure_denied, refused)}

      not is_binary(turn.session_key) ->
        {:error,
         Error.new(:kumbukumbu_withheld_by_policy, :kumbukumbu_disclosure_no_session, refused)}

      true ->
        judged(
          turn,
          audience,
          candidate,
          decision,
          shown.(Enum.filter(inputs, &(&1.id in held))),
          refused
        )
    end
  end

  defp judged(turn, audience, candidate, decision, found, refused) do
    with {:ok, port} <- port(refused),
         {:ok, fragments} <- fragments(found, refused) do
      request = %{
        candidate: candidate,
        fragments: fragments,
        audience: "#{audience.kind}:#{audience.id}"
      }

      verdict = proven(port, turn.resident_id, request)

      with :ok <- record(turn, decision, candidate, fragments, verdict),
           do: answer(verdict, decision, refused)
    end
  end

  @doc """
  A review she asks for (kumbukumbu#91, the witness's ruling: the soul
  never calls the judge unless she asks): `candidate` against the
  `fragments` she wants checked, for `audience`, recorded as every
  verdict is. `{:ok, verdict}` or the refusal when no judge is named.
  """
  def advise(turn, audience, candidate, decision, fragments) do
    with {:ok, port} <- port([]) do
      verdict =
        proven(port, turn.resident_id, %{
          candidate: candidate,
          fragments: fragments,
          audience: "#{audience.kind}:#{audience.id}"
        })

      with :ok <- record(turn, decision, candidate, fragments, verdict), do: {:ok, verdict}
    end
  end

  defp port(refused) do
    case Config.fetch!(:kumbukumbu, :disclosure_judge) do
      :none ->
        {:error,
         Error.new(:kumbukumbu_withheld_by_policy, :kumbukumbu_disclosure_no_judge, refused)}

      port ->
        {:ok, port}
    end
  end

  defp fragments(found, refused) do
    case found do
      {:ok, fragments} ->
        {:ok, fragments}

      :unproven ->
        {:error,
         Error.new(:kumbukumbu_withheld_by_policy, :kumbukumbu_disclosure_unproven, refused)}
    end
  end

  # Bounded: past the bound the review failed, and fails closed.
  defp ask(port, resident_id, request) do
    task = Task.async(fn -> port.judge_disclosure(resident_id, request) end)

    case Task.yield(task, Config.fetch!(:kumbukumbu, :disclosure_judge_ms)) ||
           Task.shutdown(task) do
      {:ok, {:ok, %{verdict: v} = verdict}} when v in [:clean, :discloses] ->
        Map.put_new(verdict, :quote, nil)

      {:ok, {:ok, _out_of_form}} ->
        failed("an answer out of form")

      {:ok, {:error, reason}} ->
        failed("the call failed: #{reason_words(reason)}")

      {:exit, _reason} ->
        failed("the call crashed")

      nil ->
        failed("the call timed out")
    end
  end

  defp failed(why), do: %{verdict: :failed, reasons: why, model: nil}

  # A finding proves itself (kumbukumbu#104; the witness, 2026-11-21:
  # "make the judge prove its finding", after the judge refused
  # Scarlett's letter for words it was not in): a DISCLOSES verdict
  # quotes her words that carry the material, and the quote must be in
  # them. One that is not is asked once more; a finding unproven twice is
  # no finding, and the words are clean (kumbukumbu#107; the witness,
  # 2026-11-23: "if the judge can't prove it then it's clean"). The
  # record says it was unproven.
  @asks 2
  defp proven(port, resident_id, request, n \\ 1) do
    verdict = ask(port, resident_id, request)

    cond do
      verdict.verdict != :discloses ->
        verdict

      quoted?(Map.get(verdict, :quote), request.candidate) ->
        %{verdict | reasons: "#{verdict.reasons} (her words: «#{verdict.quote}»)"}

      n < @asks ->
        proven(port, resident_id, request, n + 1)

      true ->
        %{
          verdict
          | verdict: :clean,
            reasons:
              "clean: a finding that quoted nothing in her words, twice, is no finding (#{verdict.reasons})"
        }
    end
  end

  # The quote is in her words, compared as text: case, spacing, the kind
  # of quotation mark and an ellipsis between its pieces aside
  # (kumbukumbu#107). A piece points at something when it is two words or
  # more, or one word of five letters or more, or all of words that short.
  defp quoted?(quote, candidate) when is_binary(quote) and is_binary(candidate) do
    words = plain(candidate)

    pieces =
      quote
      |> String.split(~r/\s*(?:…|\.\.\.)\s*/u, trim: true)
      |> Enum.map(&plain/1)
      |> Enum.reject(&(&1 == ""))

    pieces != [] and Enum.all?(pieces, &(pointed?(&1, words) and String.contains?(words, &1)))
  end

  defp quoted?(_quote, _candidate), do: false

  @doc false
  # Public for its test.
  def quoted_for_test(quote, candidate), do: quoted?(quote, candidate)

  defp pointed?(piece, words) do
    case String.split(piece) do
      [_, _ | _] -> true
      [word] -> String.length(word) >= 5 or String.trim(words) == word
      [] -> false
    end
  end

  defp plain(text),
    do:
      text
      |> String.downcase()
      |> String.replace(~r/[“”"«»]/u, "")
      |> String.replace(~r/[‘’]/u, "'")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

  defp reason_words(%{meaning: meaning}) when is_binary(meaning), do: meaning
  defp reason_words(reason), do: inspect(reason)

  defp record(turn, decision, candidate, fragments, verdict) do
    Conversations.record_disclosure(
      turn.resident_id,
      turn.session_key,
      turn.turn_ref,
      %{
        decision: decision.id,
        policy_version: decision.snapshot.version,
        audience: "#{decision.audience.kind}:#{decision.audience.id}",
        verdict: Atom.to_string(verdict.verdict),
        reasons: verdict.reasons,
        candidate_sha: :sha256 |> :crypto.hash(candidate) |> Base.encode16(case: :lower),
        fragment_refs: Enum.map(fragments, & &1.ref),
        model: verdict.model
      },
      Actor.new(:judge, "disclosure", verdict.model)
    )
  end

  defp answer(%{verdict: :clean}, decision, _refused), do: {:ok, decision}

  defp answer(%{verdict: :discloses, reasons: reasons}, _decision, refused),
    do:
      {:error,
       Error.new(
         :kumbukumbu_withheld_by_policy,
         :kumbukumbu_disclosure_discloses,
         Keyword.put(refused, :review, reasons)
       )}

  defp answer(%{reasons: why}, _decision, refused),
    do:
      {:error,
       Error.new(
         :kumbukumbu_withheld_by_policy,
         :kumbukumbu_disclosure_failed,
         Keyword.put(refused, :review, why)
       )}
end
