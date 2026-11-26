defmodule OneiroiWeb.SuccessionController do
  @moduledoc """
  The witness's side of a succession (janus#3 to #5): where it stands,
  his proposal and its withdrawal, and the backup repository the whole
  original is exported to before any cutover. Her acts are her tools;
  nothing here answers for her.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Config.Secret
  alias Oneiroi.Janus
  alias OpenApiSpex.Schema

  tags(["succession"])

  plug(:witnessed)

  operation(:show,
    summary: "The resident's latest succession, or null",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the succession", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}), do: json(conn, %{succession: view(Janus.succession(id))})

  operation(:propose,
    summary:
      "Propose a succession; it waits on her yes. dry_run rehearses everything but the replacement",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the proposal", "application/json",
       %Schema{
         type: :object,
         required: [:note],
         properties: %{note: %Schema{type: :string}, dry_run: %Schema{type: :boolean}}
       }},
    responses: [created: {"the succession", "application/json", %Schema{type: :object}}]
  )

  def propose(conn, %{"id" => id, "note" => note} = params) when is_binary(note) do
    case Janus.propose(id, params["dry_run"] == true, note, actor(conn)) do
      {:ok, _} -> conn |> put_status(201) |> json(%{succession: view(Janus.succession(id))})
      other -> respond(conn, other)
    end
  end

  def propose(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_succession_propose_note_required,
        "note is required"
      )

  operation(:withdraw,
    summary: "Withdraw a proposal she has not answered",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "withdrawn"]
  )

  def withdraw(conn, %{"id" => id, "note" => note}) when is_binary(note),
    do: respond(conn, Janus.withdraw(id, note, actor(conn)))

  def withdraw(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_succession_withdraw_note_required,
        "note is required"
      )

  operation(:backup,
    summary:
      "Set the repository the whole original is exported to before a cutover, with a token shown to nobody again",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the repository", "application/json",
       %Schema{
         type: :object,
         required: [:url],
         properties: %{url: %Schema{type: :string}, token: %Schema{type: :string}}
       }},
    responses: [
      ok:
        {"set, with what its host says: visibility private, public or unknown; push yes or unknown",
         "application/json", %Schema{type: :object}}
    ]
  )

  def backup(conn, %{"id" => id, "url" => url} = params) when is_binary(url) do
    token = params["token"] && Secret.wrap(params["token"])

    case Janus.set_backup(id, url, token, actor(conn)) do
      {:ok, check} -> json(conn, check)
      other -> respond(conn, other)
    end
  end

  def backup(conn, _params),
    do:
      problem(conn, 422, :fields_required, :web_succession_backup_url_required, "url is required")

  # What the screens read: the token never.
  defp view(nil), do: nil

  defp view(row),
    do: %{
      episode: row.episode,
      state: row.state,
      dry_run: row.dry_run,
      proposed_by: row.proposed_by,
      proposed_note: row.proposed_note,
      proposed_at: row.proposed_at,
      opened_note: row.opened_note,
      opened_at: row.opened_at,
      forked: not is_nil(row.copy_id),
      fork_sequence: row.fork_sequence,
      forked_at: row.forked_at,
      fork_failure: row.fork_failure,
      backup_url: row.backup_url,
      backup_visibility: row.backup_visibility,
      backup_push: row.backup_push,
      ended_note: row.ended_note,
      ended_at: row.ended_at
    }

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_succession_not_witnessed
          )
        )
        |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")
  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
end
