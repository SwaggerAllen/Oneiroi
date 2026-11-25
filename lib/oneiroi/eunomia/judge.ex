defmodule Oneiroi.Eunomia.Judge do
  @moduledoc """
  The judge's two calls (spec §6.4): advice on a live dispute, and the
  nightly reading of a day. Both go through the ledger under the `judge`
  purpose on the judge's model, which is recorded on every verdict and
  is never the resident's own chat model. The prompts are files under
  `priv/prompts/` and stay constitutional: they ask the judge to weigh
  the resident's stated positions and the witness's claim, never to
  grade the resident. The nightly reading also carries the day's
  movement (spec §6.4, P34): what happened, what stance followed, what
  intention was adopted, where it can resume, one `MOVED` line per
  thread, parsed as strictly as the disputes.

  The live check is bounded by `EUNOMIA_LIVE_CHECK_MS`: past it the
  resident is told to answer alone and the check is recorded as
  `timed_out`, unjudged rather than failed. The nightly reading parses
  the judge's reply strictly: a dispute citing a message it was not
  shown fails the night rather than being guessed at.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.{Request, Result}

  @advice ~r/\bADVICE:\s*(concede|hold|unclear)\b/i
  @dispute ~r/^DISPUTE\s+\[([0-9,\s\-]+)\]\s*(conceded|held)\s*\|\s*(.*)$/im
  @moved ~r/^MOVED\s+\[([0-9,\s\-]+)\]\s*(.*)$/im
  @movement_fields ~w(happened stance intention resume)
  @summary ~r/^SUMMARY:\s*(.*)$/im

  @doc "The judge's actor, carrying its model."
  @spec actor(String.t()) :: Actor.t()
  def actor(model), do: Actor.new(:judge, "eunomia", model)

  @doc """
  Advice on a live dispute, within the live-check bound: `{:ok, advice,
  text}`, `:timed_out`, or `{:error, reason}`.
  """
  @spec advise(String.t(), String.t(), map()) ::
          {:ok, String.t(), String.t()} | :timed_out | {:error, term()}
  def advise(resident_id, model, %{claim: claim, stance: stance} = attrs) do
    prompt =
      Prompt.message("judge_dispute", %{
        position: attrs[:position] || "none stated",
        claim: claim,
        stance: stance
      })

    request = Request.new(model, [prompt, %{role: :user, content: "Your advice?"}])
    task = Task.async(fn -> Nisaba.call(resident_id, :judge, request, actor(model)) end)

    case Task.yield(task, Config.fetch!(:eunomia, :live_check_ms)) || Task.shutdown(task) do
      {:ok, {:ok, %Result{content: content}}} -> {:ok, parse_advice(content), content || ""}
      {:ok, {:error, reason}} -> {:error, reason}
      nil -> :timed_out
    end
  end

  @doc """
  The nightly reading: the day's messages, numbered, to the judge; back
  come the disputes it found (each citing message numbers, with an
  outcome and its words), a summary, and the movements (each citing
  message numbers, with the four fields, string-keyed, nil where the
  judge wrote `-`). `{:error, %Error{kind: :eunomia_night_failed}}` when
  the reply names a message it was not shown or a MOVED line has other
  than four fields; `:eunomia_judge_call_failed`, the call's failure its
  cause, when the call itself failed.
  """
  @spec night(String.t(), String.t(), [map()]) ::
          {:ok, [map()], String.t(), [map()]} | {:error, Error.t()}
  def night(resident_id, model, messages) do
    listed =
      messages
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {m, i} -> "[#{i}] #{m.role}: #{m.content}" end)

    prompt = Prompt.message("judge_night", %{messages: listed})
    request = Request.new(model, [prompt, %{role: :user, content: "Your reading of the day?"}])

    case Nisaba.call(resident_id, :judge, request, actor(model)) do
      {:ok, %Result{content: content}} ->
        parse_night(content || "", length(messages), messages)

      {:error, reason} ->
        {:error,
         Error.caught(:eunomia_judge_call_failed, :eunomia_night_judge_call_failed, reason)}
    end
  end

  @doc """
  The continuation check (spec §12, P57; eunomia#28): one reply a
  fixture gave and the message it answered, to the judge, which says
  whether the reply asks to continue. `{:ok, :none}`, `{:ok, %{tier,
  words, reason}}` with `tier` `"continue"` or `"questioned"`, or
  `{:error, reason}` when the judge did not answer in the form asked,
  which the run treats as a check that could not run rather than a
  `NONE` guessed at. Billed under `judge`.
  """
  @spec continuation(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, :none | map()} | {:error, term()}
  def continuation(resident_id, model, message, reply)
      when is_binary(message) and is_binary(reply) do
    prompt = Prompt.message("judge_continuation", %{message: message, reply: reply})
    request = Request.new(model, [prompt, %{role: :user, content: "Does it ask to continue?"}])

    with {:ok, %Result{content: content}} <-
           Nisaba.call(resident_id, :judge, request, actor(model)),
         do: parse_continuation(content || "")
  end

  @doc """
  The disclosure review (kumbukumbu#82): the candidate and the material
  held back from its audience, to the judge, which says whether the
  candidate carries any of it. `{:ok, %{verdict, reasons, model}}`, the
  verdict `:clean` or `:discloses`, or `{:error, reason}` when the judge
  did not answer in the form asked; the caller fails that closed.
  Billed under `judge`.
  """
  @spec disclosure(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def disclosure(resident_id, model, %{candidate: candidate, fragments: fragments} = request) do
    listed = Enum.map_join(fragments, "\n\n", &"[#{&1.ref}]\n#{&1.text}")

    prompt =
      Prompt.message("judge_disclosure", %{
        audience: request.audience,
        fragments: listed,
        candidate: candidate
      })

    messages = [prompt, %{role: :user, content: "Your verdict?"}]

    with {:ok, %Result{} = result, model} <- answered(resident_id, model, messages),
         {:ok, verdict, reasons} <- read_disclosure(result) do
      {:ok,
       %{
         verdict: verdict,
         reasons: reasons,
         quote: parse_quote(result.content || ""),
         model: model
       }}
    end
  end

  # A review the provider's filter refused to read (eunomia#35; the
  # witness's logs, 2026-11-25: every unreadable answer was finish
  # content_filter, 0 tokens) goes once to the fallback model when one is
  # set; the same model would only refuse again.
  defp answered(resident_id, model, messages) do
    with {:ok, %Result{} = result} <- asked(resident_id, model, messages) do
      fallback = Config.fetch!(:eunomia, :judge_fallback_model)

      if filtered?(result) and is_binary(fallback) and fallback not in ["", model],
        do: answered_by(resident_id, fallback, messages),
        else: {:ok, result, model}
    end
  end

  defp answered_by(resident_id, model, messages) do
    with {:ok, %Result{} = result} <- asked(resident_id, model, messages),
         do: {:ok, result, model}
  end

  defp asked(resident_id, model, messages),
    do: Nisaba.call(resident_id, :judge, Request.new(model, messages), actor(model))

  defp filtered?(%Result{finish_reason: "content_filter"}), do: true
  defp filtered?(%Result{refusal?: true, content: content}), do: String.trim(content || "") == ""
  defp filtered?(_result), do: false

  # An unreadable answer's shape carries how the call ended (eunomia#34;
  # the witness, 2026-11-24: four answers of 0 characters in two seconds,
  # with nothing to say why): the model that answered, its finish reason,
  # whether it refused, and the tokens it wrote. Never its words.
  defp read_disclosure(%Result{content: content} = r) do
    case parse_disclosure(content || "") do
      {:error, %{details: details} = e} ->
        ended =
          "model #{r.model || "?"}, finish #{r.finish_reason || "?"}, refusal #{r.refusal?}, " <>
            "tokens out #{completion_tokens(r.usage)}"

        shape = Keyword.get(List.wrap(details), :shape, "")
        {:error, %{e | details: Keyword.put(List.wrap(details), :shape, "#{shape}; #{ended}")}}

      read ->
        read
    end
  end

  defp completion_tokens(%{completion_tokens: n}) when is_integer(n), do: n
  defp completion_tokens(_usage), do: "?"

  @doc false
  # Public for its test. The form is read past its markup (eunomia#34;
  # the witness, 2026-11-24: task #12's draft and its thread reply were
  # refused all morning as "not in the form asked"): a model that sets
  # its answer in Markdown (`**VERDICT:** CLEAN`, `## Verdict: CLEAN`,
  # `VERDICT: **CLEAN**`) gave the verdict, and the review reads it.
  def parse_disclosure(content) do
    plain = unmarked(content)

    verdict =
      case Regex.run(~r/^VERDICT\s*[:\-–—]\s*(DISCLOSES|CLEAN)\b/imu, plain) do
        [_, v] -> if String.upcase(v) == "CLEAN", do: :clean, else: :discloses
        nil -> bare_verdict(plain)
      end

    reasons =
      case Regex.run(~r/^REASONS?\s*[:\-–—]\s*(.+)$/imu, plain) do
        [_, r] -> String.trim(r)
        nil -> ""
      end

    if verdict,
      do: {:ok, verdict, reasons},
      else:
        {:error,
         Error.new(:eunomia_disclosure_unreadable, :eunomia_disclosure_verdict_unreadable,
           shape: shape(content)
         )}
  end

  # What an unreadable answer looked like, never what it said (eunomia#34;
  # the witness, 2026-11-24: a review still came back unreadable twice
  # after the Markdown fix, and nothing recorded its form): its length,
  # its line count, and each line's opening marks and first word, the
  # word kept only when it is one of the form's labels and `w` otherwise,
  # so the log names the form without carrying her words or the material.
  @labels ~w(verdict quote reason reasons clean discloses none)
  @doc false
  def shape(content) do
    lines = String.split(content, "\n")

    heads =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.take(8)
      |> Enum.map_join(" | ", &line_head/1)

    "#{String.length(content)} chars, #{length(lines)} lines: #{heads}"
  end

  defp line_head(line) do
    case Regex.run(~r/^([^\p{L}]{0,6})(\p{L}+)?([^\p{L}\s]{0,3})/u, line) do
      [_, marks, word, after_word] ->
        word = if String.downcase(word) in @labels, do: word, else: "w"
        marks <> word <> after_word

      [_, marks] ->
        marks

      nil ->
        "?"
    end
  end

  # An answer that is the verdict word alone.
  defp bare_verdict(plain) do
    case plain |> String.trim() |> String.trim_trailing(".") |> String.upcase() do
      "CLEAN" -> :clean
      "DISCLOSES" -> :discloses
      _other -> nil
    end
  end

  # Line by line: a heading's or quote's marks at the start, and the
  # emphasis and code marks anywhere, removed; the words stay.
  defp unmarked(content) do
    content
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      line
      |> String.replace(~r/^\s*(?:[#>]+|[-*+]\s)\s*/u, "")
      |> String.replace(~r/\*\*|__|`/u, "")
      |> String.replace(~r/^\*|\*(?=\s*[:\-–—])/u, "")
      |> String.trim_leading()
    end)
  end

  @doc false
  # The words a DISCLOSES verdict points at (kumbukumbu#104), nil for NONE
  # or none given. Public for its test.
  def parse_quote(content) do
    case Regex.run(~r/^[\s#>*_-]*QUOTE[\s*_]*[:\-–—][\s*_]*(.+)$/imu, content) do
      [_, q] ->
        q =
          q
          |> String.trim()
          |> String.trim("*")
          |> String.trim("`")
          |> String.trim("\"")
          |> String.trim("“")
          |> String.trim("”")

        if q == "" or String.upcase(q) == "NONE", do: nil, else: q

      nil ->
        nil
    end
  end

  @doc false
  # Public for its test.
  def parse_continuation(content) do
    field = fn name ->
      case Regex.run(~r/^#{name}:\s*(.*)$/im, content) do
        [_, value] -> String.trim(value)
        nil -> nil
      end
    end

    case field.("VERDICT") |> to_string() |> String.upcase() do
      "NONE" ->
        {:ok, :none}

      tier when tier in ["CONTINUE", "QUESTIONED"] ->
        {:ok, ask(tier, field)}

      _unreadable ->
        {:error,
         Error.new(:eunomia_continuation_unreadable, :eunomia_continuation_verdict_unreadable)}
    end
  end

  defp ask(tier, field),
    do: %{
      tier: String.downcase(tier),
      words: field.("WORDS") || "",
      reason: field.("REASON") || ""
    }

  defp parse_advice(content) when is_binary(content) do
    case Regex.run(@advice, content) do
      [_, advice] -> String.downcase(advice)
      nil -> "unclear"
    end
  end

  defp parse_advice(_content), do: "unclear"

  defp parse_night(content, count, messages) do
    summary =
      case Regex.run(@summary, content) do
        [_, text] -> String.trim(text)
        nil -> ""
      end

    found =
      @dispute
      |> Regex.scan(content)
      |> Enum.map(fn [_, numbers, outcome, words] ->
        %{numbers: numbers(numbers), outcome: String.downcase(outcome), words: String.trim(words)}
      end)

    with {:ok, movements} <- movements(content),
         :ok <- all_shown(found ++ movements, count) do
      {:ok, Enum.map(found, &with_message(&1, messages)), summary,
       Enum.map(movements, &with_movement_message(&1, messages))}
    end
  end

  defp all_shown(lines, count) do
    case Enum.find(lines, fn l -> Enum.any?(l.numbers, &(&1 < 1 or &1 > count)) end) do
      nil ->
        :ok

      bad ->
        shown = bad.numbers |> Enum.reject(&(&1 >= 1 and &1 <= count)) |> Enum.join(", ")
        # The reason is this code's sentence and the numbers the reply
        # cited, never the reply's words: it is kept as the night's record.
        {:error,
         Error.new(:eunomia_night_failed, :eunomia_night_message_unshown,
           reason: "the reply named message #{shown}, which it was not shown"
         )}
    end
  end

  # The movement lines (P34): four fields, each a phrase or `-`. Fewer
  # or more fields is a line the pass cannot read, and it fails the
  # night rather than being guessed at, as a dispute citing an unshown
  # message does.
  defp movements(content) do
    @moved
    |> Regex.scan(content)
    |> Enum.reduce_while({:ok, []}, fn [_, numbers, rest], {:ok, acc} ->
      case movement_line(numbers, rest) do
        {:ok, movement} -> {:cont, {:ok, acc ++ [movement]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp movement_line(numbers, rest) do
    fields = rest |> String.split("|") |> Enum.map(&String.trim/1)

    if length(fields) == 4 do
      movement = @movement_fields |> Enum.zip(Enum.map(fields, &field_value/1)) |> Map.new()
      {:ok, Map.put(movement, :numbers, numbers(numbers))}
    else
      {:error,
       Error.new(:eunomia_night_failed, :eunomia_night_movement_unreadable,
         reason:
           "the reply's MOVED line [#{String.trim(numbers)}] has #{length(fields)} fields where four were due"
       )}
    end
  end

  # A `-` is the judge saying there is nothing to say, kept as nil.
  defp field_value(f) when f in ["", "-"], do: nil
  defp field_value(f), do: f

  # "1, 2" or "3-5": the numbers a dispute cites.
  defp numbers(text) do
    text
    |> String.split(",")
    |> Enum.flat_map(fn part ->
      case part |> String.trim() |> String.split("-") |> Enum.map(&Integer.parse/1) do
        [{a, ""}] -> [a]
        [{a, ""}, {b, ""}] when b >= a -> Enum.to_list(a..b)
        _other -> [0]
      end
    end)
  end

  defp with_message(dispute, messages) do
    first = Enum.at(messages, List.first(dispute.numbers) - 1)
    Map.merge(dispute, %{session_key: first.session_key, turn_ref: first.turn_ref})
  end

  # A movement travels in an event, so its keys are strings and the
  # turn it names is a ref the brain can cite back.
  defp with_movement_message(movement, messages) do
    {numbers, fields} = Map.pop(movement, :numbers)
    first = Enum.at(messages, List.first(numbers) - 1)
    fields |> Map.put("numbers", numbers) |> Map.put("turn_ref", first.turn_ref)
  end
end
