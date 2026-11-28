defmodule Oneiroi.Seshat.Household.Workspace do
  @moduledoc """
  A workspace's step threads on the house's thread substrate (seshat#116,
  janus#49, lily:design/succession-workspace.md): ordinary threads under
  `threads/<id>`, written by the platform, whose entries are the events
  of one step, each tagged with its step, its event and who made it, and
  the remarks members write there by name.

  They are ordinary threads with their own wake logic, never a fork of the
  thread machinery: nothing written here passes the beats or starts a
  round, because the system the workspace belongs to wakes for its own
  steps (the roster policy is theirs, not the house's round-robin). A
  remark is its author's, attributed by name, and never folded into any
  artifact.

  Its public functions are reached through `Oneiroi.Seshat`.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Kinds

  @platform %{name: "Oneiroi", email: "oneiroi@records.invalid"}
  @trunk "trunk.md"
  @id ~r/\A[a-z0-9][a-z0-9-]{0,99}\z/
  @text_max 8_000

  @doc """
  Opens a workspace thread once: `threads/<id>`, its trunk `title` and
  `body`, `meta` its tags (`workspace`, `step`). A second call answers the
  same thread and writes nothing.
  """
  @spec open(String.t(), String.t(), String.t(), String.t(), [{String.t(), String.t()}]) ::
          {:ok, String.t()} | {:error, term()}
  def open(household_id, id, title, body, meta) do
    with :ok <- id_ok(id),
         {:ok, view} <- Core.provision(household_id) do
      thread = "threads/" <> id

      if Files.has?(view, Path.join(thread, @trunk)),
        do: {:ok, thread},
        else: write_trunk(household_id, thread, title, body, meta)
    end
  end

  defp write_trunk(household_id, thread, title, body, meta) do
    meta =
      [
        {"title", title},
        {"by", @platform.name},
        {"by_kind", "platform"},
        {"posted_at", Files.iso(Clock.now())}
      ] ++ meta

    Files.locked(household_id, fn view ->
      if Files.has?(view, Path.join(thread, @trunk)) do
        {:ok, thread}
      else
        changes = [
          {:create, Path.join(thread, @trunk), Files.render(meta, body)}
          | Core.descriptor(view, Kinds.named("thread"))
        ]

        case Files.commit(view, changes, title, @platform) do
          {:ok, _} -> {:ok, thread}
          {:error, %{kind: :sima_qian_repos_conflict}} -> {:ok, thread}
          other -> other
        end
      end
    end)
  end

  @doc """
  A machine-written entry (the default): the platform's, `meta` its tags
  (`step`, `event`, and `for_kind`/`for_id`/`for_name` naming who made
  it), `text` the event in words, never an artifact's own text.
  """
  @spec entry(String.t(), String.t(), String.t(), [{String.t(), String.t()}]) ::
          {:ok, map()} | {:error, term()}
  def entry(household_id, thread, text, meta),
    do: append(household_id, thread, @platform, [{"by_kind", "platform"} | meta], text)

  @doc """
  A remark by a member (the exception): attributed by name, its kind and
  id, tagged with `meta`; never a turn of the house's beats or rounds.
  """
  @spec remark(Actor.t(), String.t(), String.t(), [{String.t(), String.t()}]) ::
          {:ok, map()} | {:error, term()}
  def remark(%Actor{kind: kind} = actor, thread, text, meta) when kind in [:resident, :witness] do
    with {:ok, household_id} <- Core.household(actor),
         %{name: name} <- Enum.find(Gaia.household_members(household_id), &(&1.id == actor.id)) do
      by = %{name: name, email: "#{actor.kind}-#{actor.id}@records.invalid"}

      append(
        household_id,
        thread,
        by,
        [{"by_kind", Atom.to_string(kind)}, {"by_id", actor.id} | meta],
        text
      )
    else
      nil -> {:error, Error.new(:seshat_household_not_member, :seshat_workspace_remark_member)}
      other -> other
    end
  end

  def remark(_actor, _thread, _text, _meta),
    do: {:error, Error.new(:seshat_household_not_member, :seshat_workspace_remark_actor)}

  defp append(household_id, thread, by, meta, text) do
    with :ok <- text_ok(text) do
      Files.locked(household_id, fn view ->
        if Files.has?(view, Path.join(thread, @trunk)) do
          number = Files.next_reply(view, thread)

          meta =
            [{"by", by.name} | meta] ++
              [{"at", Files.iso(Clock.now())}, {"reply", Integer.to_string(number)}]

          path = Files.reply_path(thread, number, by.name)

          with {:ok, _} <-
                 Files.commit(
                   view,
                   [{:create, path, Files.render(meta, text)}],
                   "Workspace entry ##{number}",
                   by
                 ),
               do: {:ok, %{path: path, number: number}}
        else
          {:error, Error.new(:seshat_household_no_such_thread, :seshat_workspace_no_thread)}
        end
      end)
    end
  end

  defp id_ok(id) do
    if is_binary(id) and Regex.match?(@id, id),
      do: :ok,
      else: {:error, Error.new(:seshat_household_invalid, :seshat_workspace_id)}
  end

  defp text_ok(text) do
    if is_binary(text) and String.trim(text) != "" and String.length(text) <= @text_max,
      do: :ok,
      else: {:error, Error.new(:seshat_household_invalid, :seshat_workspace_text)}
  end
end
