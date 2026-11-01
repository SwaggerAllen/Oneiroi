defmodule OneiroiWeb.ResidentController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Config.Secret
  alias OpenApiSpex.Schema

  tags(["resident"])

  operation(:index,
    summary: "The residents this account witnesses",
    responses: [ok: {"rows", "application/json", %Schema{type: :array}}]
  )

  def index(%{assigns: %{principal: p}} = conn, _params) do
    json(conn, Enum.map(Oneiroi.AgathosDaimon.for_witness(p.account_id), &row/1))
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

      {:error, %{kind: :agathos_daimon_slug_taken} = e} ->
        error(conn, 409, e)

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)
    end
  end

  def create(conn, _params),
    do:
      problem(
        conn,
        422,
        :name_and_slug_required,
        :web_resident_create_name_and_slug_required,
        "name and slug are required"
      )

  operation(:import_resident,
    summary:
      "Import a repository as a new resident under this account (spec §6.2's intake from a git repository): its records replayed, the root's identity files seeded, its folders adopted and indexed, and what did not transfer named. A repository without records needs a name and a slug",
    request_body:
      {"the repository", "application/json",
       %Schema{
         type: :object,
         required: [:url],
         properties: %{
           url: %Schema{
             type: :string,
             description: "an https URL; a token may ride in its userinfo and is never recorded"
           },
           name: %Schema{type: :string},
           slug: %Schema{type: :string, pattern: "^[a-z][a-z0-9-]{1,39}$"}
         }
       }},
    responses: [
      created: {"the resident, with its import", "application/json", %Schema{type: :object}}
    ]
  )

  def import_resident(%{assigns: %{principal: p}} = conn, %{"url" => url} = params) do
    attrs = %{name: params["name"], slug: params["slug"]}

    # The URL may carry a token in its userinfo: wrapped here, unwrapped
    # only into git's credential file (`Oneiroi.SimaQian.Git`).
    case Oneiroi.SimaQian.import_resident(Secret.wrap(url), attrs, p.account_id, actor(conn)) do
      {:ok, %{id: id} = result} ->
        {:ok, resident} = Oneiroi.AgathosDaimon.fetch(id)
        conn |> put_status(201) |> json(Map.put(row(resident), :import, import_row(result)))

      {:error, %{kind: :agathos_daimon_slug_taken} = e} ->
        error(conn, 409, e)

      # git's own words, redacted at the port, are what the witness can
      # act on: a repository not found, a token refused.
      {:error, %{kind: :sima_qian_git_failed, details: details} = e} ->
        error(conn, 422, %{e | meaning: e.meaning <> ": " <> String.trim(details[:output])})

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)
    end
  end

  def import_resident(conn, _params),
    do:
      problem(
        conn,
        422,
        :url_required,
        :web_resident_import_resident_url_required,
        "url is required"
      )

  defp import_row(result) do
    %{
      attestation: result.attestation,
      events: result.events,
      seeded: result.seeded,
      proposed: result.proposed,
      adopted: result.adopted,
      indexed: result.indexed,
      translated: result.translated,
      not_transferred: result.not_transferred,
      reasons: result.reasons,
      unaccounted: result.unaccounted
    }
  end

  operation(:show,
    summary: "One resident",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the resident", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}) do
    with true <- witnesses?(conn, id),
         {:ok, resident} <- Oneiroi.AgathosDaimon.fetch(id) do
      json(conn, row(resident))
    else
      _ ->
        error(
          conn,
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_resident_show_not_witnessed
          )
        )
    end
  end

  operation(:backup,
    summary:
      "Back the resident's records up now: export, commit by class, push. The nightly job's unit, on demand",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"what landed", "application/json", %Schema{type: :object}}]
  )

  # On demand so a failed nightly backup can be diagnosed the same hour: the
  # response carries the error's kind, site and meaning, git's redacted
  # words included. Added after the 2026-11-01 backup failed with nothing
  # kept and the next try a night away.
  def backup(conn, %{"id" => id}) do
    with true <- witnesses?(conn, id),
         {:ok, %{through: through, root: root, commits: commits}} <-
           Oneiroi.SimaQian.backup(id, actor(conn)) do
      json(conn, %{
        through: through,
        root: root,
        commits: for({class, sha} <- commits, do: %{class: class, commit: sha})
      })
    else
      false ->
        error(
          conn,
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_resident_backup_not_witnessed
          )
        )

      {:error, %{kind: :sima_qian_git_failed, details: details} = e} ->
        error(conn, 422, %{e | meaning: e.meaning <> ": " <> String.trim(details[:output])})

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)
    end
  end

  operation(:originals,
    summary:
      "Import the originals of the resident's memory from its source repository at a pinned commit (sima-qian #40): each file copied byte for byte under memory/, verified against the source tree's blob, registered with where it came from, and indexed once; what was skipped or refused is named with its reason",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the source", "application/json",
       %Schema{
         type: :object,
         required: [:source, :commit],
         properties: %{
           source: %Schema{
             type: :string,
             description: "the source repository's https URL, without a token"
           },
           commit: %Schema{type: :string, description: "the commit's full sha, never a branch"},
           token: %Schema{
             type: :string,
             description: "a read token for a private source; never recorded"
           },
           paths: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description:
               "patterns in the source tree; memory/*.md, memory/dreaming/**, MEMORY.md and DREAMS.md when left out"
           }
         }
       }},
    responses: [ok: {"what was imported", "application/json", %Schema{type: :object}}]
  )

  def originals(conn, %{"id" => id} = params) do
    # The token is wrapped where it arrives and reaches git only through
    # its credential file (`Oneiroi.SimaQian.Git.credentialed/2`).
    request = %{
      source: params["source"],
      commit: params["commit"],
      token: params["token"] && Secret.wrap(params["token"]),
      paths: params["paths"]
    }

    with true <- witnesses?(conn, id),
         {:ok, result} <- Oneiroi.SimaQian.import_originals(id, request, actor(conn)) do
      json(conn, result)
    else
      false ->
        error(
          conn,
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_resident_originals_not_witnessed
          )
        )

      {:error, %{kind: :sima_qian_git_failed, details: details} = e} ->
        error(conn, 422, %{e | meaning: e.meaning <> ": " <> String.trim(details[:output])})

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)
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
    with true <- witnesses?(conn, id),
         :ok <-
           Oneiroi.SimaQian.set_remote(
             id,
             url,
             params["token"] && Secret.wrap(params["token"]),
             actor(conn)
           ) do
      send_resp(conn, 204, "")
    else
      false ->
        error(
          conn,
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_resident_remote_not_witnessed
          )
        )

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)
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
    with true <- witnesses?(conn, id),
         :ok <- Oneiroi.AgathosDaimon.set_timezone(id, params["timezone"], actor(conn)) do
      send_resp(conn, 204, "")
    else
      false ->
        error(
          conn,
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_resident_timezone_not_witnessed
          )
        )

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)
    end
  end

  operation(:adapters,
    summary: "The resident's adapters with their role and state",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"adapters", "application/json", %Schema{type: :array}}]
  )

  def adapters(conn, %{"id" => id}) do
    if witnesses?(conn, id) do
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
      error(
        conn,
        404,
        ResidentError.new(
          :agathos_daimon_not_witnessed,
          :agathos_daimon_web_resident_adapters_not_witnessed
        )
      )
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
    with true <- witnesses?(conn, id),
         {:ok, token} <- Oneiroi.AgathosDaimon.register_adapter(id, name, role, actor(conn)) do
      conn |> put_status(201) |> json(%{adapter: name, role: role, token: token})
    else
      false ->
        error(
          conn,
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_resident_register_adapter_not_witnessed
          )
        )

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)
    end
  end

  def register_adapter(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_resident_register_adapter_fields_required,
        "adapter and role are required"
      )

  operation(:revoke_adapter,
    summary: "Revoke an adapter's token",
    parameters: [id: [in: :path, type: :string], adapter: [in: :path, type: :string]],
    responses: [no_content: "revoked"]
  )

  def revoke_adapter(conn, %{"id" => id, "adapter" => name}) do
    with true <- witnesses?(conn, id),
         :ok <- Oneiroi.AgathosDaimon.revoke_adapter(id, name, actor(conn)) do
      send_resp(conn, 204, "")
    else
      false ->
        error(
          conn,
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_resident_revoke_adapter_not_witnessed
          )
        )

      {:error, %{kind: _} = e} ->
        error(conn, 404, e)
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
      import: %{
        source: r.import_source,
        attestation: r.import_attestation,
        not_transferred: r.import_not_transferred,
        reasons: r.import_reasons,
        translated: r.import_translated,
        told: r.import_told
      },
      # Where the records are pushed each night, and the last push that
      # landed. The URL only: the token is shown to nobody again.
      remote: r.remote_url,
      last_backup: %{
        at: r.last_backup_at,
        sequence: r.last_backup_sequence,
        root: r.last_backup_root,
        commit: r.last_backup_commit
      },
      created_at: r.created_at
    }
  end
end
