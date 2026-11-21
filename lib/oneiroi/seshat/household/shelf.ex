defmodule Oneiroi.Seshat.Household.Shelf do
  @moduledoc """
  The shelf paged (seshat#61), the files list, who is working, a
  resident's activity, and the house's name for citations (gaia#44).

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Reading
  alias Oneiroi.Seshat.HouseWorking
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Sunna

  @contract "CONTRACT.md"
  @beats "BEATS.md"
  @page 50

  @doc false
  def shelf(%Actor{} = actor, from \\ 0) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, view} <- Core.provision(household_id) do
      ballots = Map.new(Gaia.household_contract(household_id).ballots, &{&1.thread, &1})

      threads =
        view
        |> Files.thread_ids()
        |> Enum.map(&Files.thread_summary(view, &1, ballots))
        |> Enum.filter(&Reading.visible?(actor, household_id, &1.ids))
        # Last updated first (the witness, 2026-11-19: "sort by last
        # updated, not created"): a reply brings its thread up.
        |> Enum.sort_by(&{&1.last_reply_at || &1.posted_at, &1.path}, :desc)

      documents =
        view
        |> Files.documents()
        |> Enum.filter(&Reading.visible?(actor, household_id, [&1.by_id]))

      items = threads ++ documents
      page = items |> Enum.drop(from) |> Enum.take(@page)

      {:ok,
       %{
         household_id: household_id,
         # Its name for citations (gaia#44), nil until a witness names it.
         slug: Gaia.household_slug(household_id),
         contract: @contract,
         total: length(items),
         from: from,
         next: if(from + @page < length(items), do: from + @page),
         threads: Enum.filter(page, &(&1.kind == "thread")) |> Enum.map(&Map.delete(&1, :ids)),
         documents: Enum.filter(page, &(&1.kind != "thread"))
       }}
    end
  end

  @doc false
  def files(%Actor{} = actor) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, view} <- Core.provision(household_id) do
      ballots = Map.new(Gaia.household_contract(household_id).ballots, &{&1.thread, &1})

      own =
        for {path, title} <- [
              {@contract, "The household contract"},
              {@beats, "The household's beats"}
            ],
            Files.has?(view, path),
            do: file_row("house", path, title, nil, nil)

      threads =
        view
        |> Files.thread_ids()
        |> Enum.map(&Files.thread_summary(view, &1, ballots))
        |> Enum.filter(&Reading.visible?(actor, household_id, &1.ids))
        |> Enum.map(
          &file_row("thread", &1.path, &1.title, &1.last_reply_at || &1.posted_at, &1.by,
            created_at: &1.posted_at,
            versions: &1.replies + 1
          )
        )

      documents =
        view
        |> Files.documents()
        |> Enum.filter(&Reading.visible?(actor, household_id, [&1.by_id]))
        |> Enum.map(&file_row(&1.kind, &1.path, &1.title, &1.posted_at, &1.by))

      rows = own ++ threads ++ documents
      present = rows |> Enum.map(& &1.kind) |> MapSet.new()

      kinds =
        ([%{kind: "house", label: "The house"}] ++
           for(
             k <- Kinds.shelf(),
             Map.get(k, :household, false),
             do: %{kind: k.kind, label: house_label(k)}
           ))
        |> Enum.with_index()
        |> Enum.map(fn {k, i} -> Map.put(k, :position, i) end)

      {:ok,
       %{
         household_id: household_id,
         kinds: Enum.filter(kinds, &MapSet.member?(present, &1.kind)),
         documents: rows,
         unadopted: []
       }}
    end
  end

  # In a resident's records human/ is the witness's own ("Yours"); in the
  # house it is every witness's, a folder each (seshat#81).
  defp house_label(%{kind: "human"}), do: "Witnesses"

  defp house_label(k), do: k.label

  defp file_row(kind, path, title, at, by, extra \\ []) do
    %{
      kind: kind,
      path: path,
      title: title,
      status: nil,
      bytes: nil,
      versions: Keyword.get(extra, :versions, 1),
      written_at: at,
      created_at: Keyword.get(extra, :created_at, at),
      written_by: by,
      missing_at: nil,
      note: nil
    }
  end

  @doc false
  def working(%Actor{} = actor) do
    with {:ok, household_id} <- Core.household(actor) do
      names = Map.new(Gaia.household_members(household_id), &{&1.id, &1.name})

      {:ok,
       for(
         w <- HouseWorking.list(household_id),
         do: Map.put(w, :name, Map.get(names, w.resident_id))
       )}
    end
  end

  @doc false
  def activity(%Actor{} = actor, resident_id \\ nil) do
    with {:ok, household_id} <- Core.household(actor) do
      members = Gaia.household_members(household_id)
      names = Map.new(members, &{&1.id, &1.name})
      residents = for %{kind: "resident", id: id} <- members, do: id
      ids = filtered(members, residents, resident_id)
      own = if actor.kind == :resident, do: [actor.id], else: residents
      name = &Map.get(names, &1)

      rows =
        wake_rows(ids, household_id, own, name) ++
          token_rows(household_id, ids, name) ++
          letter_rows(Enum.filter(ids, &(&1 in own)), name, viewer(actor))

      {:ok,
       rows
       |> Enum.reject(&is_nil(&1.at))
       |> Enum.sort_by(& &1.at, {:desc, DateTime})
       |> Enum.take(150)}
    end
  end

  # One resident, by id or by name; anything else, every resident.
  defp filtered(_members, residents, nil), do: residents

  defp filtered(members, residents, wanted) do
    key = String.downcase(to_string(wanted))

    case Enum.find(
           members,
           &(&1.kind == "resident" and (&1.id == wanted or String.downcase(&1.name || "") == key))
         ) do
      %{id: id} -> [id]
      nil -> residents
    end
  end

  # A wake of the house's is everyone's to see; one of her own life (a
  # letter's, free time's) is hers and her witness's.
  defp wake_rows(ids, household_id, own, name) do
    for w <- Sunna.wakes(ids, 150),
        w.household_id == household_id or w.resident_id in own,
        do: %{
          kind: wake_kind(w),
          at: w.at,
          resident_id: w.resident_id,
          name: name.(w.resident_id),
          channel: w.channel,
          causes: w.causes,
          delivered: w.delivered,
          read_at: w.read_at,
          wake_id: w.wake_id
        }
  end

  # Not delivered: a mention banked (muted), or letters the hourly bound
  # held for a later tick (sunna#72).
  defp wake_kind(%{delivered: true}), do: "wake"

  defp wake_kind(%{channel: "mention"}), do: "mention"

  defp wake_kind(_held), do: "held"

  defp token_rows(household_id, ids, name) do
    for t <- Gaia.round_turns(household_id),
        t.resident_id in ids,
        do: %{
          kind: "token",
          at: t.issued_at,
          resident_id: t.resident_id,
          name: name.(t.resident_id),
          thread: t.thread,
          round: t.round,
          turn_id: t.turn_id,
          until: t.expires_at,
          outcome: t.outcome,
          spent_at: t.spent_at
        }
  end

  # A sealed letter's read state is its parties' alone (kumbukumbu#93):
  # a witness sees that it was sent, never whether it was read.
  defp viewer(%Actor{kind: :resident, id: id}), do: {:resident, id}
  defp viewer(%Actor{id: id}), do: {:account, id}

  defp letter_rows(ids, name, viewer) do
    for id <- ids,
        l <- Kumbukumbu.letter_envelopes(id, 50),
        l = if(Kumbukumbu.letter_view(l, viewer) == :whole, do: l, else: %{l | read_by: []}),
        do: %{
          kind: "letter",
          at: l.sent_at,
          resident_id: id,
          name: name.(id),
          number: l.number,
          from: l.from_name,
          to: l.to_name,
          in_reply_to: l.in_reply_to,
          read_by: l.read_by || []
        }
  end

  @doc false
  def name(%Actor{} = actor, slug) do
    with {:ok, household_id} <- Core.household(actor),
         :ok <- Gaia.name_household(household_id, to_string(slug || ""), actor),
         do: shelf(actor)
  end
end
