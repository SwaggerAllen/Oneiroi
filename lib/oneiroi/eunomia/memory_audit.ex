defmodule Oneiroi.Eunomia.MemoryAudit do
  @moduledoc """
  The weekly memory audit (spec §6.4, F15): the judge reads what Honcho
  concluded about the person, at most `EUNOMIA_AUDIT_CONCLUSIONS` of
  them (150, David's), against the resident's held positions and soul,
  and flags the ones that read as drift. A flag waits on the witness:
  approved, the conclusion is deleted from Honcho; deleted, it stays.
  Each with a note. The judge inspects and never grades the grader.
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
  alias Oneiroi.Proteus
  alias Oneiroi.Scope

  @flag ~r/^FLAG\s+\[(\d+)\]\s*\|\s*(.*)$/im
  @summary ~r/^SUMMARY:\s*(.*)$/im

  @doc "Runs the audit once; nothing concluded calls no model."
  def run(resident_id, %Actor{} = actor) do
    ref = fresh_ref()
    model = Judgements.judge_model(resident_id)

    case Proteus.conclusions(resident_id, Config.fetch!(:eunomia, :audit_conclusions)) do
      {:ok, []} ->
        record(resident_id, ref, 0, 0, nil, "nothing concluded yet", actor)

      {:ok, conclusions} ->
        case judge(resident_id, model, conclusions) do
          {:ok, flags, summary} ->
            Enum.each(flags, &raise_flag(resident_id, ref, &1, model))
            record(resident_id, ref, length(conclusions), length(flags), model, summary, actor)

          {:error, reason} ->
            fail(resident_id, ref, reason, actor)
        end

      {:error, reason} ->
        fail(resident_id, ref, reason, actor)
    end
  end

  defp judge(resident_id, model, conclusions) do
    positions =
      resident_id
      |> Judgements.held_positions()
      |> Enum.map_join("\n", &"- ##{&1.number} #{&1.statement}")

    soul =
      resident_id
      |> AgathosDaimon.identity_context()
      |> Enum.filter(fn {name, _} -> name == "SOUL.md" end)
      |> Enum.map_join("\n", &elem(&1, 1))

    listed =
      conclusions
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {c, i} -> "[#{i}] #{c.content}" end)

    prompt =
      Prompt.message("judge_audit", %{
        positions: if(positions == "", do: "none stated", else: positions),
        soul: if(soul == "", do: "not written yet", else: soul),
        conclusions: listed
      })

    request = Request.new(model, [prompt, %{role: :user, content: "Your audit?"}])

    case Nisaba.call(resident_id, :judge, request, Judge.actor(model)) do
      {:ok, %Result{content: content}} -> parse(content || "", conclusions)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse(content, conclusions) do
    count = length(conclusions)

    flags =
      @flag
      |> Regex.scan(content)
      |> Enum.map(fn [_, n, reason] -> {String.to_integer(n), String.trim(reason)} end)

    summary =
      case Regex.run(@summary, content) do
        [_, text] -> String.trim(text)
        nil -> ""
      end

    case Enum.find(flags, fn {n, _} -> n < 1 or n > count end) do
      nil ->
        found =
          Enum.map(flags, fn {n, reason} ->
            c = Enum.at(conclusions, n - 1)
            %{conclusion_id: c.id, conclusion: c.content, reason: reason}
          end)

        {:ok, found, summary}

      {n, _} ->
        {:error, "the reply flagged conclusion #{n}, which it was not shown"}
    end
  end

  defp raise_flag(resident_id, audit_ref, flag, model) do
    dispatch(%Commands.RaiseAuditFlag{
      actor: Judge.actor(model),
      at: Clock.now(),
      id: resident_id,
      ref: fresh_ref(),
      audit_ref: audit_ref,
      conclusion_id: flag.conclusion_id,
      conclusion: flag.conclusion,
      reason: flag.reason
    })
  end

  defp record(resident_id, ref, conclusions, flagged, model, summary, actor) do
    command = %Commands.RunAudit{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      ref: ref,
      conclusions: conclusions,
      flagged: flagged,
      judge_model: model,
      summary: summary
    }

    with {:ok, _} <- dispatch(command), do: {:ok, ref}
  end

  defp fail(resident_id, ref, reason, actor) do
    text = reason_text(reason)

    command = %Commands.FailAudit{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      ref: ref,
      reason: text
    }

    with {:ok, _} <- dispatch(command),
         do: {:error, Error.new(:eunomia_audit_failed, reason: text)}
  end

  @doc "The witness approves a flag: the conclusion is deleted from Honcho, then the flag is closed with the note."
  def approve(resident_id, ref, note, %Actor{} = actor) do
    with :ok <- witness_only(actor),
         {:ok, flag} <- open_flag(resident_id, ref),
         :ok <- Proteus.delete_conclusion(resident_id, flag.conclusion_id) do
      command = %Commands.ApproveAuditFlag{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        ref: ref
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "The witness deletes a flag: the conclusion stays; the flag is closed with the note."
  def delete(resident_id, ref, note, %Actor{} = actor) do
    with :ok <- witness_only(actor),
         {:ok, _flag} <- open_flag(resident_id, ref) do
      command = %Commands.DeleteAuditFlag{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        ref: ref
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "The runs, newest first, and every flag, open first."
  def audits(resident_id) do
    Scope.resident(resident_id, fn ->
      flags = Store.audit_flags()

      %{
        runs: Store.audits(),
        open: Enum.filter(flags, &is_nil(&1.decision)),
        decided: Enum.filter(flags, &(&1.decision != nil))
      }
    end)
  end

  defp open_flag(resident_id, ref) do
    case Scope.resident(resident_id, fn -> Enum.find(Store.audit_flags(), &(&1.ref == ref)) end) do
      nil -> {:error, Error.new(:eunomia_no_such_flag, ref: ref)}
      %{decision: nil} = flag -> {:ok, flag}
      _decided -> {:error, Error.new(:eunomia_flag_decided, ref: ref)}
    end
  end

  defp witness_only(%Actor{kind: :witness}), do: :ok
  defp witness_only(%Actor{}), do: {:error, Error.new(:eunomia_not_the_witness)}

  defp fresh_ref, do: 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp reason_text(%{kind: kind}) when is_atom(kind), do: Atom.to_string(kind)
  defp reason_text(text) when is_binary(text), do: text
  defp reason_text(other), do: other |> inspect() |> String.slice(0, 200)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} -> {:ok, events}
      {:error, :no_such_flag} -> {:error, Error.new(:eunomia_no_such_flag, ref: command.ref)}
      {:error, reason} -> {:error, reason}
    end
  end
end
