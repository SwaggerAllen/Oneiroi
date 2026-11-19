defmodule OneiroiWeb.BooksTest do
  @moduledoc "seshat#98: the witness imports an EPUB as the request's body with its rights note, and reads her books with their places; another account cannot."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.EpubFixture
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    witness = Actor.new(:witness, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", witness)
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, id: resident.id, token: token}
  end

  defp conn_as(token),
    do: build_conn() |> put_req_header("authorization", "Bearer " <> token)

  test "an EPUB in, the book listed with its place; a rights note required; another account refused",
       ctx do
    bytes = EpubFixture.build([{"One", ["First."]}, {"Two", ["Second."]}])

    assert %{"slug" => "the-long-field", "chapters" => 2} =
             conn_as(ctx.token)
             |> put_req_header("content-type", "application/epub+zip")
             |> post(
               "/v1/residents/#{ctx.id}/books?rights=public-domain&source=field.epub",
               bytes
             )
             |> json_response(200)

    assert %{
             "books" => [
               %{"title" => "The Long Field", "chapters" => 2, "read" => 0, "current" => nil}
             ],
             "rights" => ["public-domain", "house-shareable", "purchased-drm-free"]
           } = conn_as(ctx.token) |> get("/v1/residents/#{ctx.id}/books") |> json_response(200)

    assert conn_as(ctx.token)
           |> put_req_header("content-type", "application/epub+zip")
           |> post("/v1/residents/#{ctx.id}/books", bytes)
           |> json_response(422)

    other = Fixtures.account!()
    {:ok, token, _} = Oneiroi.Gaia.issue_token(other.id, "t", Actor.new(:witness, other.id))
    assert conn_as(token) |> get("/v1/residents/#{ctx.id}/books") |> json_response(404)
  end
end
