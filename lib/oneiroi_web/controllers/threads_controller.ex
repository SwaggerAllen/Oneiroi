defmodule OneiroiWeb.ThreadsController do
  @moduledoc """
  A resident's own threads as her witness reads and writes them
  (seshat#106 to #108): the space the two of them share, in her
  records, the house's thread layout with the dyad's audience. Its
  witness's post or reply wakes her chat.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["threads"])

  plug(:witnessed)

  operation(:index,
    summary:
      "Her own threads, the last active first (seshat#106): each with its title, who posted it, the document it is on if any, its replies and the last reply's time and author; with doc, that document's one thread or null (seshat#107)",
    parameters: [id: [in: :path, type: :string], doc: [in: :query, type: :string]],
    responses: [ok: {"the threads", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id, "doc" => doc}) when is_binary(doc) do
    case Seshat.thread_for_document(actor(conn), id, doc) do
      {:ok, thread} -> json(conn, %{thread: thread})
      {:error, e} -> error(conn, 422, e)
    end
  end

  def index(conn, %{"id" => id}) do
    case Seshat.threads(actor(conn), id) do
      {:ok, threads} -> json(conn, threads)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:show,
    summary:
      "One of her threads whole: its trunk, every reply in order, the document it is on as it stands (path, latest commit, still present), and the text her turn reads",
    parameters: [
      id: [in: :path, type: :string],
      path: [in: :query, type: :string, required: true]
    ],
    responses: [ok: {"the thread", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id} = params) do
    case Seshat.thread_read(actor(conn), id, to_string(params["path"] || "")) do
      {:ok, t} -> json(conn, t)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:create,
    summary:
      "Post in her threads as her witness: a thread (title, content), or with doc (a path in her records) that document's one thread, opened the first time and answered after, content a reply in it; wakes her chat (seshat#108)",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the post", "application/json",
       %Schema{
         type: :object,
         properties: %{
           title: %Schema{type: :string},
           content: %Schema{type: :string},
           doc: %Schema{type: :string}
         }
       }},
    responses: [created: {"the thread", "application/json", %Schema{type: :object}}]
  )

  def create(conn, %{"id" => id} = params) do
    case Seshat.thread_post(actor(conn), id, Map.take(params, ~w(title content doc))) do
      {:ok, t} -> conn |> put_status(201) |> json(t)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:reply,
    summary: "Reply in one of her threads as her witness; wakes her chat (seshat#108)",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the reply", "application/json",
       %Schema{
         type: :object,
         required: [:thread, :content],
         properties: %{
           thread: %Schema{type: :string},
           content: %Schema{type: :string},
           in_reply_to: %Schema{type: :integer}
         }
       }},
    responses: [created: {"the reply", "application/json", %Schema{type: :object}}]
  )

  def reply(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ~w(content in_reply_to))

    case Seshat.thread_reply(actor(conn), id, to_string(params["thread"] || ""), attrs) do
      {:ok, r} -> conn |> put_status(201) |> json(r)
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_threads_not_witnessed
          )
        )
        |> halt()
  end
end
