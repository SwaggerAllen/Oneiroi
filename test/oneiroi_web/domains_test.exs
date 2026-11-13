defmodule OneiroiWeb.DomainsTest do
  @moduledoc """
  Domains per message over HTTP (P23-R1, kumbukumbu#72): a session no
  longer opens with one; the composer names a turn's domain as it is
  sent, the tag route renames one after, and the session and its
  messages say the domain they are in.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Oneiroi.Actor.new(:witness, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    Fake.reply("Heard.", for: resident.id)
    on_exit(fn -> Fake.clear(for: resident.id) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, account: account}
  end

  test "a session opens without a domain; asking for one is refused", %{conn: conn, id: id} do
    assert %{"error" => %{"kind" => "kumbukumbu_domain_per_message"}} =
             conn
             |> post("/v1/residents/#{id}/sessions", %{kind: "free_time", domain: "business"})
             |> json_response(422)
  end

  test "the composer names a turn's domain, the tag route renames it, and both read back",
       %{conn: conn, id: id, account: account} do
    assert %{"key" => key} =
             conn |> post("/v1/residents/#{id}/sessions", %{}) |> json_response(201)

    ref = "composer-ref-1"

    assert %{"state" => _taken} =
             conn
             |> post("/v1/residents/#{id}/sessions/#{key}/turns", %{
               text: "the deck",
               client_ref: ref,
               domain: "business"
             })
             |> json_response(202)

    messages = fn ->
      conn |> get("/v1/residents/#{id}/sessions/#{key}") |> json_response(200)
    end

    assert eventually(fn -> length(messages.()["messages"]) == 2 end)
    person = "account:" <> account.id

    assert %{"messages" => [said, answer]} = messages.()

    assert %{"domain" => %{"slug" => "business", "person" => ^person}, "domain_tagged" => true} =
             said

    assert %{"domain" => %{"slug" => "business"}} = answer

    session = fn ->
      conn
      |> get("/v1/residents/#{id}/sessions")
      |> json_response(200)
      |> Enum.find(&(&1["key"] == key))
    end

    assert %{"domain" => %{"slug" => "business", "whose" => "witness"}} = session.()

    # Renamed after the fact.
    assert conn
           |> post("/v1/residents/#{id}/sessions/#{key}/turns/#{ref}/domain", %{
             domain: "recovery"
           })
           |> response(204)

    assert %{"messages" => [%{"domain" => %{"slug" => "recovery"}}, _]} = messages.()
    assert %{"domain" => %{"slug" => "recovery"}} = session.()

    assert %{"error" => %{"kind" => "kumbukumbu_domain_invalid"}} =
             conn
             |> post("/v1/residents/#{id}/sessions/#{key}/turns/#{ref}/domain", %{
               domain: "Recovery!"
             })
             |> json_response(422)

    # Back to the common room.
    assert conn
           |> post("/v1/residents/#{id}/sessions/#{key}/turns/#{ref}/domain", %{domain: nil})
           |> response(204)

    assert %{"domain" => nil} = session.()
  end

  defp eventually(check, tries \\ 50) do
    cond do
      check.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(50)
        eventually(check, tries - 1)
    end
  end
end
