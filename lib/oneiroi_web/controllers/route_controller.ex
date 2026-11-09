defmodule OneiroiWeb.RouteController do
  @moduledoc """
  Routes and profiles (xenia#19). The witness reads every route with
  whether it can fire, defines a route of hers, asks a run, and makes,
  names, revokes and restores profiles. The `reader` adapter reads what
  it is to do, route by route, and says a run of hers landed or failed.
  A `brain` token is refused: she acts through her tools.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Apsu.Ops
  alias Oneiroi.Xenia
  alias OpenApiSpex.Schema

  tags(["reader"])

  @reader_actions ~w(reader landed failed)a

  plug(:allowed)

  operation(:index,
    summary:
      "Every route, the built-ins then hers, with whether it can fire; her runs; the profiles with their routes",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"routes", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}) do
    json(conn, %{
      routes: Xenia.routes(id),
      runs: Enum.map(Xenia.route_runs(id), &run/1),
      profiles: Xenia.profiles(id),
      landing: Xenia.route_landing_kinds(id)
    })
  end

  defp run(r),
    do: %{
      number: r.number,
      key: r.key,
      state: r.state,
      note: r.note,
      asked_by: r.asked_by,
      asked_at: r.asked_at,
      path: r.path,
      reason: r.reason,
      done_at: r.done_at
    }

  operation(:define,
    summary:
      "Define or rewrite a route of hers: a source, on request, through a profile that stands, landing in a kind she writes",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the route", "application/json",
       %Schema{
         type: :object,
         required: [:key, :prompt, :profile, :kind],
         properties: %{
           key: %Schema{type: :string},
           label: %Schema{type: :string},
           prompt: %Schema{type: :string},
           profile: %Schema{type: :string},
           kind: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [created: {"the route", "application/json", %Schema{type: :object}}]
  )

  def define(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ~w(key label prompt profile kind direction cadence))

    case Xenia.define_route(id, attrs, params["note"], actor(conn)) do
      {:ok, key} -> conn |> put_status(201) |> json(%{key: key})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:ask,
    summary: "Ask a run of a route of hers; the reader fires it on its next wait",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, properties: %{note: %Schema{type: :string}}}},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def ask(conn, %{"id" => id, "key" => key} = params) do
    case Xenia.ask_route(id, key, params["note"], actor(conn)) do
      {:ok, n} -> conn |> put_status(201) |> json(%{number: n})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:set_profile,
    summary:
      "Make a profile, or name one: one origin, whom it is signed in as; the witness's alone",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the profile", "application/json",
       %Schema{
         type: :object,
         required: [:key],
         properties: %{
           key: %Schema{type: :string},
           label: %Schema{type: :string},
           origin: %Schema{type: :string},
           signed_in_as: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "set"]
  )

  def set_profile(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ~w(key label origin signed_in_as))

    case Xenia.set_profile(id, attrs, params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:revoke,
    summary: "Revoke a profile, with why: its routes stay, unable to fire",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "revoked"]
  )

  def revoke(conn, %{"id" => id, "key" => key} = params) do
    case Xenia.revoke_profile(id, key, params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:restore,
    summary: "Restore a revoked profile, with why",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "restored"]
  )

  def restore(conn, %{"id" => id, "key" => key} = params) do
    case Xenia.restore_profile(id, key, params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:reader,
    summary:
      "What the reader is to do, route by route: each with its runner, profile, state and what waits; and the profiles",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the routes", "application/json", %Schema{type: :object}}]
  )

  def reader(conn, %{"id" => id}) do
    with %AdapterPrincipal{adapter: name} <- conn.assigns[:principal],
         do: Ops.beat("#{id}:#{name}")

    json(conn, Xenia.reader(id))
  end

  operation(:landed,
    summary: "A run of a route of hers landed: its title and text, written where the route says",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the reading", "application/json",
       %Schema{
         type: :object,
         required: [:text],
         properties: %{title: %Schema{type: :string}, text: %Schema{type: :string}}
       }},
    responses: [ok: {"where it landed", "application/json", %Schema{type: :object}}]
  )

  def landed(conn, %{"id" => id, "number" => n} = params) do
    with {number, ""} <- Integer.parse(to_string(n)),
         {:ok, path} <-
           Xenia.land_route(id, number, params["title"], params["text"], actor_of(conn)) do
      json(conn, %{path: path})
    else
      {:error, e} -> error(conn, 422, e)
      _bad -> number_invalid(conn)
    end
  end

  operation(:failed,
    summary: "The reader could not do a run of hers, and says why",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, properties: %{reason: %Schema{type: :string}}}},
    responses: [no_content: "recorded"]
  )

  def failed(conn, %{"id" => id, "number" => n} = params) do
    with {number, ""} <- Integer.parse(to_string(n)),
         :ok <-
           Xenia.fail_route(id, number, params["reason"] || "no reason given", actor_of(conn)) do
      send_resp(conn, 204, "")
    else
      {:error, e} -> error(conn, 422, e)
      _bad -> number_invalid(conn)
    end
  end

  defp number_invalid(conn),
    do:
      problem(
        conn,
        422,
        :number_invalid,
        :web_route_number_invalid,
        "the run's number is a whole number"
      )

  defp actor_of(%{assigns: %{principal: %AdapterPrincipal{adapter: name}}}),
    do: Actor.new(:hands, name)

  defp actor_of(conn), do: actor(conn)

  defp allowed(%{params: %{"id" => id}} = conn, _opts) do
    action = Phoenix.Controller.action_name(conn)

    ok? =
      case adapter(conn) do
        %AdapterPrincipal{resident_id: ^id, role: "reader"} -> action in @reader_actions
        %AdapterPrincipal{} -> false
        nil -> witnesses?(conn, id) and action not in [:landed, :failed]
      end

    if ok?,
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_routes_not_witnessed
          )
        )
        |> halt()
  end
end
