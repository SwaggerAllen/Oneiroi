defmodule OneiroiWeb.BookController do
  @moduledoc """
  A resident's books (seshat#98): the witness imports a DRM-free EPUB,
  sent as the request's body (`application/epub+zip`) with its rights
  note in the query, and reads the list with each book's place. The
  witness's alone (the witness, 2026-11-19: "witness only"); she reads
  them with book_read.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["library"])

  plug(:witnessed)

  # An EPUB is a book, not an archive of a life: far under the import's bound.
  @max_bytes 64 * 1024 * 1024

  operation(:index,
    summary:
      "Her books (seshat#98): each with its chapters' count, how many she has read, and her place",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"books", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}) do
    books =
      for b <- Seshat.books(id) do
        {:ok, %{chapters: chapters}} = Seshat.book_contents(id, b.slug)

        %{
          slug: b.slug,
          title: b.title,
          author: b.author,
          rights: b.rights,
          caveat: b.caveat,
          chapters: length(chapters),
          read: Enum.count(chapters, &(&1.state == "read")),
          current: b.current,
          read_at: b.read_at,
          imported_at: b.imported_at
        }
      end

    json(conn, %{books: books, rights: Seshat.book_rights()})
  end

  operation(:import,
    summary:
      "Import a DRM-free EPUB into her library (seshat#98): the file as the body (application/epub+zip), `rights` (public-domain, house-shareable or purchased-drm-free) and optional `caveat` and `source` in the query",
    parameters: [
      id: [in: :path, type: :string],
      rights: [in: :query, type: :string, required: true],
      caveat: [in: :query, type: :string],
      source: [in: :query, type: :string]
    ],
    responses: [ok: {"the book", "application/json", %Schema{type: :object}}]
  )

  def import(conn, %{"id" => id} = params) do
    case body(conn, [], 0) do
      {:ok, bytes, conn} ->
        case Seshat.book_import(
               id,
               bytes,
               Map.take(params, ~w(rights caveat source)),
               actor(conn)
             ) do
          {:ok, b} ->
            json(conn, %{
              slug: b.slug,
              title: b.title,
              author: b.author,
              chapters: length(b.units)
            })

          {:error, e} ->
            error(conn, 422, e)
        end

      {:too_large, conn} ->
        problem(
          conn,
          413,
          :too_large,
          :web_book_too_large,
          "the book is larger than #{@max_bytes} bytes"
        )

      {:error, conn} ->
        problem(
          conn,
          400,
          :unreadable_body,
          :web_book_body_unreadable,
          "the upload did not arrive whole"
        )
    end
  end

  defp body(conn, acc, size) do
    case Plug.Conn.read_body(conn, length: 1_000_000, read_length: 1_000_000) do
      {:ok, chunk, conn} -> more(conn, [acc | chunk], size + byte_size(chunk), :done)
      {:more, chunk, conn} -> more(conn, [acc | chunk], size + byte_size(chunk), :more)
      {:error, _reason} -> {:error, conn}
    end
  end

  defp more(conn, _acc, size, _state) when size > @max_bytes, do: {:too_large, conn}
  defp more(conn, acc, _size, :done), do: {:ok, IO.iodata_to_binary(acc), conn}
  defp more(conn, acc, size, :more), do: body(conn, acc, size)

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(:agathos_daimon_not_witnessed, :agathos_daimon_web_book_not_witnessed)
        )
        |> halt()
  end
end
