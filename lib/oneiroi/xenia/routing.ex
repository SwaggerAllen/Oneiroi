defmodule Oneiroi.Xenia.Routing do
  @moduledoc """
  Routes and profiles as both parties and the reader act on them
  (xenia#19). The registry is `Oneiroi.Xenia.Routes`; this is where a
  route meets what it moves: what each built-in has waiting for the
  reader, read from the systems that own it, served only while the
  route's profile stands; her routes defined, asked, landed and failed;
  the witness's profiles made, revoked and restored.

  What the reader is handed for a route comes from the registry and the
  profile, never from the route's prompt: the prompt is the one field a
  party writes freely, and it travels as the text of the request alone.
  A landing goes where the route says, as `<folder>/<key>-<number>.md`,
  whatever the reader sends with it.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.Xenia.Commands
  alias Oneiroi.Xenia.Error
  alias Oneiroi.Xenia.Inbox
  alias Oneiroi.Xenia.ProfilesRouter
  alias Oneiroi.Xenia.Routes
  alias Oneiroi.Xenia.RoutesRouter
  alias Oneiroi.Xenia.Store

  @folder "routes"

  # ---- profiles ----

  @doc """
  Every profile her routes may read through: the platform's, as the
  witness named or revoked them, then his own. Each with its origin,
  whom it is signed in as, the reader's browser folder, the sites it
  reaches, its connector, whether it is revoked, and the routes bound to
  it. Never a credential: none is held here.
  """
  def profiles(resident_id) do
    rows = Map.new(Scope.resident(resident_id, fn -> Store.profiles() end), &{&1.key, &1})
    sites = Inbox.reader_sites(resident_id)
    routes = all(resident_id, rows)

    seeded = for p <- Routes.seeded_profiles(), do: seeded(p, rows[p.key], sites)
    made = for {key, row} <- rows, not Routes.seeded_profile?(key), do: made(key, row)

    for p <- seeded ++ made do
      Map.merge(p, %{
        revoked: revoked?(rows[p.key]),
        routes: for(r <- routes, r.profile == p.key, do: r.key)
      })
    end
  end

  defp seeded(p, nil, sites), do: seeded(p, %{label: nil, signed_in_as: nil}, sites)

  defp seeded(p, row, sites),
    do: %{
      key: p.key,
      label: row.label || p.label,
      origin: p.origin,
      signed_in_as: row.signed_in_as,
      browser: p.browser,
      sites: reach(p.sites, sites),
      connector: p.connector,
      seeded: true
    }

  defp made(key, row),
    do: %{
      key: key,
      label: row.label || key,
      origin: row.origin,
      signed_in_as: row.signed_in_as,
      browser: "profile-" <> key,
      sites: List.wrap(row.origin),
      connector: nil,
      seeded: false
    }

  defp revoked?(%{revoked: true}), do: true
  defp revoked?(_row), do: false

  defp reach(:scrape, sites), do: sites.scrape
  defp reach(:research, sites), do: sites.research
  defp reach(:none, _sites), do: []

  @doc "The witness makes a profile, or names one: its label, one origin, whom it is signed in as (xenia#19)."
  def set_profile(resident_id, attrs, note, %Actor{} = actor) do
    with {:ok, profile} <- Routes.profile(attrs) do
      %Commands.SetProfile{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        key: profile["key"],
        profile: profile,
        note: note
      }
      |> dispatch(ProfilesRouter)
      |> ok()
    end
  end

  @doc "The witness revokes a profile (xenia#19): its routes stay, unable to fire, and say why."
  def revoke_profile(resident_id, key, note, %Actor{} = actor) do
    with :ok <- known_profile(resident_id, key) do
      %Commands.RevokeProfile{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        key: key,
        note: note
      }
      |> dispatch(ProfilesRouter)
      |> ok()
    end
  end

  @doc "The witness restores a revoked profile (xenia#19)."
  def restore_profile(resident_id, key, note, %Actor{} = actor) do
    with :ok <- known_profile(resident_id, key) do
      %Commands.RestoreProfile{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        key: key,
        note: note
      }
      |> dispatch(ProfilesRouter)
      |> ok()
    end
  end

  defp known_profile(resident_id, key) do
    if Enum.any?(profiles(resident_id), &(&1.key == key)),
      do: :ok,
      else: {:error, Error.new(:xenia_profile_invalid, :xenia_routing_no_such_profile)}
  end

  # ---- routes ----

  @doc """
  Every route of the house for this resident: the built-ins, then hers,
  each with whether it can fire (`state` "ready" or "unable") and, when
  it cannot, why. A route whose profile is revoked is listed, never
  dropped.
  """
  def routes(resident_id),
    do:
      all(
        resident_id,
        Map.new(Scope.resident(resident_id, fn -> Store.profiles() end), &{&1.key, &1})
      )

  defp all(resident_id, rows) do
    own =
      for r <- Scope.resident(resident_id, fn -> Store.routes() end) do
        r.descriptor
        |> Routes.from_descriptor()
        |> Map.merge(%{created_by: r.created_by, updated_by: r.updated_by})
      end

    known = MapSet.new(Enum.map(Routes.seeded_profiles(), & &1.key) ++ Map.keys(rows))

    for r <- Routes.built_in() ++ own do
      cond do
        not MapSet.member?(known, r.profile) ->
          Map.merge(r, %{state: "unable", why: "its profile #{r.profile} does not exist"})

        rows[r.profile] && rows[r.profile].revoked ->
          Map.merge(r, %{state: "unable", why: "its profile #{r.profile} is revoked"})

        true ->
          Map.merge(r, %{state: "ready", why: nil})
      end
    end
  end

  @doc """
  Defines or rewrites a route of hers (xenia#19), either party: checked
  against the safe subset with the profiles that stand and the kinds of
  her registry she writes, recorded, and written as `routes/<key>.json`.
  """
  def define(resident_id, attrs, note, %Actor{} = actor) do
    standing = for p <- profiles(resident_id), not p.revoked, do: p.key
    {writable, leaves} = landing(resident_id)

    with {:ok, descriptor} <- Routes.user_route(attrs, standing, writable, leaves),
         {:ok, _} <-
           dispatch(
             %Commands.DefineRoute{
               actor: actor,
               at: Clock.now(),
               id: resident_id,
               key: descriptor["key"],
               descriptor: descriptor,
               note: note
             },
             RoutesRouter
           ),
         :ok <- write_file(resident_id, descriptor, actor) do
      {:ok, descriptor["key"]}
    end
  end

  @doc "The kinds a route of hers may land in: hers to write, with a folder, whose approval stays in the house."
  def landing_kinds(resident_id) do
    {writable, leaves} = landing(resident_id)
    writable -- leaves
  end

  defp landing(resident_id) do
    kinds = Seshat.kinds(resident_id)

    writable =
      for k <- kinds, k.access in [:resident, "resident"], is_binary(k.folder), do: k.kind

    leaves = for k <- kinds, approvable?(k) and match?(%{"then" => _}, k[:approval]), do: k.kind
    {writable, leaves}
  end

  # The route as the file that travels (the witness's kinds-q6
  # principle, applied to routes): beside nothing of the platform's.
  # The file is the route's key, held to `[a-z][a-z0-9-]` by the safe
  # subset before it gets here, under the fixed routes/ folder.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_file(resident_id, descriptor, actor) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      folder = Path.join(dir, @folder)
      File.mkdir_p!(folder)

      file =
        Map.merge(descriptor, %{
          "updated_by" => to_string(actor.kind),
          "updated_at" => DateTime.to_iso8601(Clock.now())
        })

      File.write!(
        Path.join(folder, descriptor["key"] <> ".json"),
        Jason.encode!(file, pretty: true) <> "\n"
      )

      :ok
    end
  end

  @doc "Asks a run of a route of hers (xenia#19), either party; a route that cannot fire is refused, with why."
  def ask(resident_id, key, note, %Actor{} = actor) do
    case Enum.find(routes(resident_id), &(&1.key == key)) do
      %{built_in: true} ->
        {:error, Error.new(:xenia_no_such_route, :xenia_routing_ask_built_in)}

      %{state: "unable", why: why} ->
        {:error, Error.new(:xenia_route_unable, :xenia_routing_ask_unable, why: why)}

      %{} ->
        with {:ok, [%{number: n}]} <-
               dispatch(
                 %Commands.AskRoute{
                   actor: actor,
                   at: Clock.now(),
                   id: resident_id,
                   key: key,
                   note: note
                 },
                 RoutesRouter
               ),
             do: {:ok, n}

      nil ->
        {:error, Error.new(:xenia_no_such_route, :xenia_routing_ask_none)}
    end
  end

  @doc "Her routes' runs, newest first."
  def runs(resident_id), do: Scope.resident(resident_id, fn -> Store.route_runs(nil) end)

  @doc """
  A run's reading lands (xenia#19): the reader's title and text, written
  as `<folder>/<key>-<number>.md` of the route's kind, marked for review
  when the kind waits on him, and only that: nothing the reader sends
  chooses where it goes. A route that cannot fire lands nothing.
  """
  def land(resident_id, number, title, text, %Actor{} = actor) do
    with {:ok, run} <- open_run(resident_id, number),
         {:ok, route} <- ready_route(resident_id, run.key),
         :ok <- words(text),
         kind when is_map(kind) <- landing_kind(resident_id, route.kind),
         path = "#{kind.folder}/#{route.key}-#{number}.md",
         {:ok, _} <-
           Seshat.land(resident_id, path, document(route, run, kind, title, text), actor),
         {:ok, _} <-
           dispatch(
             %Commands.LandRoute{
               actor: actor,
               at: Clock.now(),
               id: resident_id,
               number: number,
               path: path
             },
             RoutesRouter
           ) do
      {:ok, path}
    else
      nil -> {:error, Error.new(:xenia_route_invalid, :xenia_routing_land_kind)}
      other -> other
    end
  end

  @doc "The reader could not do a run, and says why (xenia#19)."
  def fail(resident_id, number, reason, %Actor{} = actor) do
    with {:ok, _run} <- open_run(resident_id, number) do
      %Commands.FailRoute{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        reason: String.slice(to_string(reason), 0, 2_000)
      }
      |> dispatch(RoutesRouter)
      |> ok()
    end
  end

  defp open_run(resident_id, number) do
    case Scope.resident(resident_id, fn -> Store.route_run(number) end) do
      %{state: "open"} = run -> {:ok, run}
      _none -> {:error, Error.new(:xenia_no_such_route, :xenia_routing_no_open_run)}
    end
  end

  defp ready_route(resident_id, key) do
    case Enum.find(routes(resident_id), &(&1.key == key)) do
      %{state: "ready"} = r ->
        {:ok, r}

      %{why: why} ->
        {:error, Error.new(:xenia_route_unable, :xenia_routing_land_unable, why: why)}

      nil ->
        {:error, Error.new(:xenia_no_such_route, :xenia_routing_land_none)}
    end
  end

  defp words(text) when is_binary(text) and text != "", do: :ok
  defp words(_none), do: {:error, Error.new(:xenia_route_invalid, :xenia_routing_land_words)}

  defp landing_kind(resident_id, kind),
    do: Enum.find(Seshat.kinds(resident_id), &(&1.kind == kind))

  defp document(route, run, kind, title, text) do
    status = if approvable?(kind), do: "status: review\n", else: ""

    title =
      if is_binary(title) and String.trim(title) != "", do: String.trim(title), else: route.label

    """
    ---
    title: #{inspect(title)}
    route: #{route.key}
    run: #{run.number}
    thread: #{route.key}:#{run.number}
    #{status}---
    # #{title}

    #{text}
    """
  end

  # ---- the reader ----

  @doc """
  What the reader is given (xenia#19): every route with its runner, its
  state and what waits on it, and the profiles. A sink serves only what
  he approved; a route that cannot fire serves nothing. A run of a route
  of hers comes with its prompt as the request's text, and the sites and
  browser of its profile.
  """
  def reader(resident_id) do
    profiles = profiles(resident_id)
    by_key = Map.new(profiles, &{&1.key, &1})

    routes =
      for r <- routes(resident_id) do
        pending = if r.state == "ready", do: pending(resident_id, r, by_key), else: []

        %{
          key: r.key,
          label: r.label,
          direction: r.direction,
          runner: r.runner,
          kind: r.kind,
          cadence: r.cadence,
          thread_key: r.thread_key,
          built_in: r.built_in,
          profile: r.profile,
          state: r.state,
          why: r.why,
          pending: pending
        }
      end

    %{routes: routes, profiles: Enum.map(profiles, &Map.delete(&1, :routes))}
  end

  defp pending(id, %{key: "correspondence-out"}, _p),
    do:
      for(
        r <- Inbox.replies(id, "approved"),
        r.platform != "email",
        do: %{number: r.number, platform: r.platform}
      )

  defp pending(id, %{key: "mail-out"}, _p),
    do:
      for(
        r <- Inbox.replies(id, "approved"),
        r.platform == "email",
        do: %{number: r.number, platform: r.platform}
      )

  defp pending(id, %{key: "digests"}, _p), do: numbers(Seshat.digests(id, status: "open"))
  defp pending(id, %{key: "research"}, _p), do: numbers(Seshat.researches(id, status: "open"))
  defp pending(id, %{key: "external"}, _p), do: numbers(Seshat.externals(id, status: "asked"))

  defp pending(id, %{key: "writing-out"}, _p) do
    %{to_draft: draft, to_watch: watch} = Seshat.pieces_for_reader(id)

    Enum.map(draft, &%{path: &1.path, step: "draft"}) ++
      Enum.map(watch, &%{path: &1.path, step: "watch"})
  end

  defp pending(id, %{built_in: false, key: key, prompt: prompt, profile: profile}, by_key) do
    p = by_key[profile]

    for run <- Scope.resident(id, fn -> Store.route_runs("open") end), run.key == key do
      %{number: run.number, prompt: prompt, sites: p.sites, browser: p.browser}
    end
  end

  defp pending(_id, _scheduled, _p), do: []

  defp numbers(rows), do: Enum.map(rows, &%{number: &1.number})

  # Her registry's word on a kind (seshat#49, #51), gates applied.
  defp approvable?(kind), do: Map.get(kind, :approvable) == true

  defp dispatch(command, router) do
    case router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:xenia_dispatch_failed, :xenia_routing_dispatch_failed, reason)}
    end
  end

  defp ok({:ok, _events}), do: :ok
  defp ok(other), do: other
end
