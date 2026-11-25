defmodule Oneiroi.Brain.HouseQueue do
  @moduledoc """
  The house queue's moves as the screens and the tools make them
  (sunna#80): the artifact's head read at the moment of the move
  (`Oneiroi.Brain.QueueHeads`) and handed to the queue, which refuses or
  lapses on it (Scarlett's first guard); and a `promote-to-house`
  activity finished by the promotion alone, after the library's own
  checks (her second).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Brain.QueueHeads
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna

  @doc "Takes an activity, its artifact's head read now."
  def take(household_id, task, act, %Actor{} = actor),
    do: Sunna.queue_take(household_id, task, act, actor, head: head(household_id, task, act))

  @doc "Finishes an activity, its artifact's head read now; `pin` defaults to that head."
  def finish(household_id, task, act, attrs, %Actor{} = actor) do
    head = head(household_id, task, act)
    attrs = attrs |> Map.put(:head, head) |> Map.put_new(:pin, head)
    Sunna.queue_finish(household_id, task, act, Map.delete(attrs, :promoted), actor)
  end

  @doc "Decides a review on what the reviewer read: `pin` (the head now when not named), the head read now beside it."
  def decide(household_id, task, act, attrs, %Actor{} = actor) do
    head = head(household_id, task, act)
    # A pinned citation names its revision (sunna#99; the witness,
    # 2026-11-24: an approval of task #12's pinned document was refused
    # for naming none): with no pin given and no head to read, the
    # approval is of the revision the citation names.
    given = attrs[:pin] || head || cited_pin(household_id, task, act)
    pin = settled(household_id, task, act, given, head, actor)
    attrs = attrs |> Map.put(:head, head) |> Map.put(:pin, pin)
    Sunna.queue_decide(household_id, task, act, attrs, actor)
  end

  # A house document's citation is pinned at the house's commit when it
  # was read (`household_read`), which is not the commit that last changed
  # the file; any other write to the house since made them differ, and
  # the guard refused every decision as read on a moved document (the
  # witness, 2026-11-23: Scarlett's peer review of task #12, refused on an
  # unchanged document). The pin she read is the head when the document's
  # words at it are the words at the head (sunna#98).
  defp settled(_h, _task, _act, pin, nil, _actor), do: pin
  defp settled(_h, _task, _act, nil, _head, _actor), do: nil

  defp settled(household_id, task, act, pin, head, actor) do
    cond do
      String.starts_with?(head, pin) or String.starts_with?(pin, head) -> pin
      same_words?(household_id, task, act, pin, head, actor) -> head
      true -> pin
    end
  end

  defp same_words?(household_id, task, act, pin, head, actor) do
    with %{layers: layers} <- Sunna.queue_task(household_id, task),
         %{artifact: "house/" <> _ = cite} <- Enum.find(List.flatten(layers), &(&1.act_id == act)),
         {:ok, %{path: path}} <- Seshat.house_citation(cite),
         {:ok, %{content: then}} <- Seshat.household_read(actor, path, at: pin),
         {:ok, %{content: now}} <- Seshat.household_read(actor, path, at: head) do
      then == now
    else
      _cannot_tell -> false
    end
  end

  @doc """
  Promotes a file of the resident's to the house and finishes the
  `promote-to-house` activity it stands for with the copy and the commit
  promoted. The promotion runs first and on its own terms; a refusal
  leaves the activity where it was.
  """
  def promote(%Actor{kind: :resident} = actor, path, household_id, task, act, attrs) do
    with {:ok, p} <- Seshat.household_promote(actor, path, attrs) do
      pin = p.source |> String.split("@") |> List.last()

      case Sunna.queue_finish(
             household_id,
             task,
             act,
             %{pin: pin, head: head(household_id, task, act), promoted: p.path},
             actor
           ) do
        :ok -> {:ok, Map.put(p, :finished, true)}
        {:error, refused} -> {:ok, p |> Map.put(:finished, false) |> Map.put(:refused, refused)}
      end
    end
  end

  @doc """
  A `promote-to-house` activity done by the platform with no agent turn
  (sunna#104; the witness, 2026-11-25: "promoting from a resident
  workspace to a house workspace shouldn't need an agent, it could just
  happen"): her own document, named by the activity, promoted as hers at
  the revision it was approved at (its citation's pin, else the latest
  approval of it in an earlier layer, else her latest draft), the house's
  terms the default. The library's own checks run as for her tool, and a
  refusal leaves the activity hers to do in a run.
  """
  def promote_activity(resident_id, household_id, task, act) do
    her = Actor.new(:resident, resident_id)

    with %{layers: layers} <- Sunna.queue_task(household_id, task),
         acts = List.flatten(layers),
         %{artifact: artifact} = a when is_binary(artifact) <-
           Enum.find(acts, &(&1.act_id == act)),
         {:ok, path} <- own_path(artifact),
         {:ok, %{finished: true}} <-
           promote(her, path, household_id, task, act, %{
             "commit" => approved_at(artifact, a, acts),
             "note" => "Promoted by the house queue: #{act}, at the revision its review approved."
           }) do
      :ok
    else
      {:ok, %{refused: refused}} -> {:error, refused}
      {:error, _} = refused -> refused
      _other -> {:error, Sunna.Error.new(:sunna_queue_invalid, :sunna_queue_promote_unnamed)}
    end
  end

  # Her own citation's path: `<slug>:<kind>/<ref>[@pin]`, resolved as
  # every citation is (`.md` added where the ref has no extension), never
  # the house's. Read by hand before, `lily:design/x` named no file
  # (14.3, 2026-11-25).
  defp own_path("house/" <> _), do: :error

  defp own_path(citation) do
    with [_slug, cited] when cited != "" <-
           citation |> String.split("@", parts: 2) |> hd() |> String.split(":", parts: 2),
         [kind, ref] <- cited |> String.trim() |> String.split("/", parts: 2) do
      {:ok, Seshat.citation_path(kind, ref)}
    else
      [_slug, cited] when cited != "" -> {:ok, Seshat.citation_path("root", String.trim(cited))}
      _other -> :error
    end
  end

  defp approved_at(artifact, a, acts) do
    bare = artifact |> String.split("@", parts: 2) |> hd()

    case String.split(artifact, "@", parts: 2) do
      [_cite, pin] when pin != "" ->
        String.trim(pin)

      _unpinned ->
        acts
        |> Enum.filter(
          &(&1.layer < a.layer and is_binary(&1.approved_pin) and is_binary(&1.artifact) and
              hd(String.split(&1.artifact, "@", parts: 2)) == bare)
        )
        |> Enum.max_by(& &1.layer, fn -> %{approved_pin: nil} end)
        |> Map.get(:approved_pin)
    end
  end

  defp cited_pin(household_id, task, act) do
    with %{layers: layers} <- Sunna.queue_task(household_id, task),
         %{artifact: artifact} when is_binary(artifact) <-
           Enum.find(List.flatten(layers), &(&1.act_id == act)),
         [_cite, pin] <- String.split(artifact, "@", parts: 2),
         pin = String.trim(pin),
         true <- pin != "" do
      pin
    else
      _none -> nil
    end
  end

  defp head(household_id, task, act) do
    with %{layers: layers} <- Sunna.queue_task(household_id, task),
         %{artifact: artifact} <- Enum.find(List.flatten(layers), &(&1.act_id == act)) do
      QueueHeads.head(household_id, artifact)
    else
      _ -> nil
    end
  end
end
