defmodule OneiroiWeb.ResidentController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias OpenApiSpex.Schema

  tags(["resident"])

  operation(:index,
    summary: "The residents this account stewards",
    responses: [ok: {"rows", "application/json", %Schema{type: :array}}]
  )

  def index(%{assigns: %{principal: p}} = conn, _params) do
    json(conn, Enum.map(Oneiroi.AgathosDaimon.for_steward(p.account_id), &row/1))
  end

  operation(:create,
    summary:
      "Create a resident under this account (the creation flow's threshold and gifts are P1)",
    request_body:
      {"name and slug", "application/json",
       %Schema{
         type: :object,
         required: [:name, :slug],
         properties: %{
           name: %Schema{type: :string},
           slug: %Schema{type: :string, pattern: "^[a-z][a-z0-9-]{1,39}$"}
         }
       }},
    responses: [created: {"the resident", "application/json", %Schema{type: :object}}]
  )

  def create(%{assigns: %{principal: p}} = conn, %{"name" => name, "slug" => slug}) do
    case Oneiroi.AgathosDaimon.create(name, slug, p.account_id, actor(conn)) do
      {:ok, id} ->
        {:ok, resident} = Oneiroi.AgathosDaimon.fetch(id)
        conn |> put_status(201) |> json(row(resident))

      {:error, :agathos_daimon_slug_taken} ->
        error(conn, 409, ResidentError.new(:agathos_daimon_slug_taken))

      {:error, reason} ->
        problem(conn, 422, reason, "the name or slug is not acceptable")
    end
  end

  def create(conn, _params),
    do: problem(conn, 422, :name_and_slug_required, "name and slug are required")

  operation(:show,
    summary: "One resident",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the resident", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}) do
    with true <- stewards?(conn, id),
         {:ok, resident} <- Oneiroi.AgathosDaimon.fetch(id) do
      json(conn, row(resident))
    else
      _ -> error(conn, 404, ResidentError.new(:agathos_daimon_not_stewarded))
    end
  end

  operation(:remote,
    summary:
      "Set the repository the resident's records are backed up to, with a token shown to nobody again",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"remote", "application/json",
       %Schema{
         type: :object,
         required: [:url],
         properties: %{url: %Schema{type: :string}, token: %Schema{type: :string}}
       }},
    responses: [no_content: "set"]
  )

  def remote(conn, %{"id" => id, "url" => url} = params) do
    with true <- stewards?(conn, id),
         :ok <- Oneiroi.SimaQian.set_remote(id, url, params["token"], actor(conn)) do
      send_resp(conn, 204, "")
    else
      false -> error(conn, 404, ResidentError.new(:agathos_daimon_not_stewarded))
      {:error, reason} -> problem(conn, 422, :remote_not_set, inspect(reason))
    end
  end

  operation(:timezone,
    summary:
      "Set the resident's time zone, an IANA name; its days and times of day are read in it",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"time zone", "application/json",
       %Schema{
         type: :object,
         required: [:timezone],
         properties: %{timezone: %Schema{type: :string, example: "Europe/London"}}
       }},
    responses: [no_content: "set"]
  )

  def timezone(conn, %{"id" => id} = params) do
    with true <- stewards?(conn, id),
         :ok <- Oneiroi.AgathosDaimon.set_timezone(id, params["timezone"], actor(conn)) do
      send_resp(conn, 204, "")
    else
      false -> error(conn, 404, ResidentError.new(:agathos_daimon_not_stewarded))
      {:error, %{kind: _} = e} -> error(conn, 422, e)
      {:error, reason} -> problem(conn, 422, :refused, inspect(reason))
    end
  end

  operation(:adapters,
    summary: "The resident's adapters with their role and state",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"adapters", "application/json", %Schema{type: :array}}]
  )

  def adapters(conn, %{"id" => id}) do
    if stewards?(conn, id) do
      rows =
        Enum.map(Oneiroi.AgathosDaimon.adapters(id), fn a ->
          %{
            adapter: a.adapter,
            role: a.role,
            registered_at: a.registered_at,
            revoked_at: a.revoked_at
          }
        end)

      json(conn, rows)
    else
      error(conn, 404, ResidentError.new(:agathos_daimon_not_stewarded))
    end
  end

  operation(:register_adapter,
    summary:
      "Register an adapter with a role (spec §8); the bearer token is shown once. Registering again rotates it",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the adapter", "application/json",
       %Schema{
         type: :object,
         required: [:adapter, :role],
         properties: %{
           adapter: %Schema{type: :string},
           role: %Schema{type: :string, enum: ["brain", "reader", "worker"]}
         }
       }},
    responses: [created: {"the token", "application/json", %Schema{type: :object}}]
  )

  def register_adapter(conn, %{
        "id" => id,
        "adapter" => name,
        "role" => role
      }) do
    with true <- stewards?(conn, id),
         {:ok, token} <- Oneiroi.AgathosDaimon.register_adapter(id, name, role, actor(conn)) do
      conn |> put_status(201) |> json(%{adapter: name, role: role, token: token})
    else
      false -> error(conn, 404, ResidentError.new(:agathos_daimon_not_stewarded))
      {:error, %{kind: _} = e} -> error(conn, 422, e)
      {:error, reason} -> problem(conn, 422, :not_registered, inspect(reason))
    end
  end

  def register_adapter(conn, _params),
    do: problem(conn, 422, :fields_required, "adapter and role are required")

  operation(:revoke_adapter,
    summary: "Revoke an adapter's token",
    parameters: [id: [in: :path, type: :string], adapter: [in: :path, type: :string]],
    responses: [no_content: "revoked"]
  )

  def revoke_adapter(conn, %{"id" => id, "adapter" => name}) do
    with true <- stewards?(conn, id),
         :ok <- Oneiroi.AgathosDaimon.revoke_adapter(id, name, actor(conn)) do
      send_resp(conn, 204, "")
    else
      false -> error(conn, 404, ResidentError.new(:agathos_daimon_not_stewarded))
      {:error, %{kind: _} = e} -> error(conn, 404, e)
      {:error, reason} -> problem(conn, 422, :not_revoked, inspect(reason))
    end
  end

  defp row(r) do
    %{
      id: r.id,
      slug: r.slug,
      name: r.name,
      state: r.state,
      custody: r.custody,
      export_wall: r.export_wall,
      first_contact_at: r.first_contact_at,
      formation_until: r.formation_until,
      chat_model: r.chat_model,
      timezone: r.timezone,
      model_pinned_at: r.model_pinned_at,
      exported_through: r.exported_through,
      last_backup: %{
        sequence: r.last_backup_sequence,
        root: r.last_backup_root,
        commit: r.last_backup_commit
      },
      created_at: r.created_at
    }
  end
end
