defmodule OneiroiWeb.ResidentController do
  use OneiroiWeb, :controller

  alias Oneiroi.Resident.Error, as: ResidentError
  alias OpenApiSpex.Schema

  tags(["resident"])

  operation(:index,
    summary: "The residents this account stewards",
    responses: [ok: {"rows", "application/json", %Schema{type: :array}}]
  )

  def index(%{assigns: %{principal: p}} = conn, _params) do
    json(conn, Enum.map(Oneiroi.Resident.for_steward(p.account_id), &row/1))
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
    case Oneiroi.Resident.create(name, slug, p.account_id, actor(conn)) do
      {:ok, id} ->
        {:ok, resident} = Oneiroi.Resident.fetch(id)
        conn |> put_status(201) |> json(row(resident))

      {:error, :resident_slug_taken} ->
        error(conn, 409, ResidentError.new(:resident_slug_taken))

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

  def show(%{assigns: %{principal: p}} = conn, %{"id" => id}) do
    with true <- id in Oneiroi.Identity.stewarded_residents(p.account_id),
         {:ok, resident} <- Oneiroi.Resident.fetch(id) do
      json(conn, row(resident))
    else
      _ -> error(conn, 404, ResidentError.new(:resident_not_stewarded))
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

  def remote(%{assigns: %{principal: p}} = conn, %{"id" => id, "url" => url} = params) do
    with true <- id in Oneiroi.Identity.stewarded_residents(p.account_id),
         :ok <- Oneiroi.Records.set_remote(id, url, params["token"], actor(conn)) do
      send_resp(conn, 204, "")
    else
      false -> error(conn, 404, ResidentError.new(:resident_not_stewarded))
      {:error, reason} -> problem(conn, 422, :remote_not_set, inspect(reason))
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
