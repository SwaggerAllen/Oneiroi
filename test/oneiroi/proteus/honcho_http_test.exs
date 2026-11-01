defmodule Oneiroi.Proteus.Honcho.HTTPTest do
  @moduledoc """
  Honcho at the HTTP boundary: every request `Honcho.HTTP` sends, held
  exactly to the deployed server's record (proteus #9); the in-memory
  Honcho refusing the names the client used to send; an unconfigured
  Honcho as an error; and the blueprint's wiring (proteus #16).
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Config.Secret
  alias Oneiroi.Proteus
  alias Oneiroi.Proteus.Honcho.Fake
  alias Oneiroi.Proteus.Honcho.HTTP
  alias Oneiroi.Proteus.Honcho.Recorded
  alias Oneiroi.Proteus.Honcho.Wire

  defmodule Server do
    @moduledoc """
    A Honcho on the loopback that records every request as the server
    reads it and answers each route in its recorded response shape,
    refusing with 422 what the record refuses.
    """
    @behaviour Plug
    import Plug.Conn

    alias Oneiroi.Proteus.Honcho.Recorded

    @impl true
    def init(agent), do: agent

    @impl true
    def call(conn, agent) do
      conn = fetch_query_params(conn)
      {:ok, raw, conn} = read_body(conn)
      path = tl(conn.path_info)

      read = %{
        method: conn.method,
        path: path,
        params: conn.query_params,
        body: if(raw == "", do: nil, else: Jason.decode!(raw))
      }

      Agent.update(agent, &(&1 ++ [read]))

      if Recorded.refusal(read),
        do: send_resp(conn, 422, ~s({"detail":"refused"})),
        else: answer(conn, conn.method, path)
    end

    @at "2026-11-01T18:28:00.000000+00:00"

    defp answer(conn, "POST", ["workspaces"]),
      do:
        json(conn, 201, "Workspace", %{
          "id" => "w",
          "uid" => "u",
          "metadata" => %{},
          "configuration" => %{},
          "created_at" => @at
        })

    defp answer(conn, method, ["workspaces", ws, "peers" | rest])
         when method in ["POST", "PUT"] and length(rest) <= 1,
         do:
           json(conn, 200, "Peer", %{
             "id" => "p",
             "uid" => "u",
             "workspace_id" => ws,
             "created_at" => @at,
             "metadata" => %{},
             "configuration" => %{}
           })

    defp answer(conn, _method, ["workspaces", _ws, "peers", peer, "card"]),
      do:
        json(conn, 200, "PeerCardResponse", %{
          "peer_card" => if(conn.query_params["target"], do: nil, else: ["Of " <> peer <> "."])
        })

    defp answer(conn, "GET", ["workspaces", _ws, "peers", observer, "context"]),
      do:
        json(conn, 200, "PeerContext", %{
          "peer_id" => observer,
          "target_id" => conn.query_params["target"],
          "representation" => "Likes rye.",
          "peer_card" => nil
        })

    defp answer(conn, "POST", ["workspaces", ws, "sessions"]),
      do:
        json(conn, 201, "Session", %{
          "id" => "s",
          "uid" => "u",
          "is_active" => true,
          "workspace_id" => ws,
          "metadata" => %{},
          "configuration" => %{},
          "created_at" => @at
        })

    defp answer(conn, "POST", ["workspaces", _ws, "sessions", _s, "messages"]),
      do: json(conn, 201, "list[Message]", [])

    defp answer(conn, "POST", [_, _, _, _, "messages", "list"]), do: page(conn, "Message", [])

    defp answer(conn, "POST", ["workspaces", ws, "conclusions", "list"]) do
      all = for n <- 1..150, do: conclusion(ws, n)
      page(conn, "Conclusion", all)
    end

    defp answer(conn, "DELETE", _path), do: send_resp(conn, 204, "")
    defp answer(conn, "POST", ["keys"]), do: json(conn, 200, "Key", %{"key" => "k"})

    defp conclusion(ws, n),
      do: %{
        "id" => "c#{n}",
        "content" => "fact #{n}",
        "observer_id" => "resident-#{ws}",
        "observed_id" => "witness-a",
        "session_id" => nil,
        "level" => "explicit",
        "source_ids" => [],
        "source_message_ids" => nil,
        "times_derived" => 1,
        "created_at" => @at
      }

    defp page(conn, item, all) do
      page = String.to_integer(conn.query_params["page"])
      size = String.to_integer(conn.query_params["size"])

      json(conn, 200, "Page[#{item}]", %{
        "items" => all |> Enum.drop((page - 1) * size) |> Enum.take(size),
        "page" => page,
        "size" => size,
        "total" => length(all),
        "pages" => div(length(all) + size - 1, size)
      })
    end

    defp json(conn, status, model, body) do
      if problem = Recorded.answer_problem(model, body), do: raise(problem)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(body))
    end
  end

  # The bodies the client sent before this record was read: the docs'
  # names. The server refuses the message's outright; the others it takes
  # by name or drops, and the fakes refuse those too, on purpose.
  @before [
    {%{method: "POST", path: ["workspaces"], params: %{}, body: %{"name" => "w"}},
     "POST /v3/workspaces: body.name is `id`'s own name: the server takes it, the fake takes only `id`"},
    {%{
       method: "POST",
       path: ["workspaces", "w", "peers"],
       params: %{},
       body: %{"name" => "p", "configuration" => %{}}
     },
     "POST /v3/workspaces/{workspace_id}/peers: body.name is `id`'s own name: the server takes it, the fake takes only `id`"},
    {%{
       method: "POST",
       path: ["workspaces", "w", "sessions"],
       params: %{},
       body: %{"id" => "s", "peer_names" => %{"p" => %{}}}
     },
     "POST /v3/workspaces/{workspace_id}/sessions: body.peer_names is `peers`'s own name: the server takes it, the fake takes only `peers`"},
    {%{
       method: "POST",
       path: ["workspaces", "w", "sessions", "s", "messages"],
       params: %{},
       body: %{
         "messages" => [
           %{"peer_name" => "p", "content" => "hi", "created_at" => "2026-11-01T18:28:00Z"}
         ]
       }
     },
     "POST /v3/workspaces/{workspace_id}/sessions/{session_id}/messages: body.messages[0].peer_name is `peer_id`'s own name, which the server does not take: it reads `peer_id`"},
    {%{
       method: "POST",
       path: ["workspaces", "w", "conclusions", "list"],
       params: %{"size" => "150"},
       body: %{"filters" => %{"observer" => "a", "observed" => "b"}}
     }, "POST /v3/workspaces/{workspace_id}/conclusions/list: query `size` is over 100"},
    {%{
       method: "POST",
       path: ["workspaces", "w", "conclusions", "list"],
       params: %{"size" => "100"},
       body: %{"filters" => %{"observer" => "a", "observed" => "b"}}
     },
     "POST /v3/workspaces/{workspace_id}/conclusions/list: body.filters.observed is not a key this list filters on"},
    {%{
       method: "GET",
       path: ["workspaces", "w", "peers", "p", "context"],
       params: %{"target" => "q", "tokens" => "800"},
       body: nil
     },
     "GET /v3/workspaces/{workspace_id}/peers/{peer_id}/context: query `tokens` is not a parameter of this route"}
  ]

  test "the record is the deployed server's commit" do
    assert Recorded.commit() == "6f91136b4e8d4b41de75f05d0cea822a1520b3a4"
  end

  test "each request the client sends is the recorded schema's, field for field" do
    agent = start_supervised!({Agent, fn -> [] end})
    start_supervised!({Bandit, plug: {Server, agent}, ip: {127, 0, 0, 1}, port: 47_817})
    at = ~U[2026-11-01 18:28:00.000000Z]
    expires = ~U[2026-11-02 18:28:00Z]

    assert :ok = HTTP.ensure_workspace("w")
    assert :ok = HTTP.ensure_peer("w", "resident-r", %{custom_instructions: "Be kind."})
    assert :ok = HTTP.ensure_session("w", "s-1", ["witness-a", "resident-r"])

    assert :ok =
             HTTP.add_messages("w", "s-1", [
               %{peer: "witness-a", content: "hi", created_at: at, turn_ref: "t1"},
               %{peer: "resident-r", content: "hello", created_at: at, turn_ref: "t1"}
             ])

    assert {:ok, false} = HTTP.turn_sent?("w", "s-1", "t1")
    assert :ok = HTTP.set_card("w", "resident-r", ["Steady."])
    assert {:ok, ["Of resident-r."]} = HTTP.get_card("w", "resident-r")
    assert {:ok, nil} = HTTP.peer_card("w", "resident-r", "witness-a")
    assert {:ok, "Likes rye."} = HTTP.context("w", "resident-r", "witness-a")
    assert {:ok, read} = HTTP.conclusions("w", "resident-r", "witness-a", 150)
    assert length(read) == 150 and hd(read) == %{id: "c1", content: "fact 1"}
    assert :ok = HTTP.delete_conclusion("w", "c1")
    assert {:ok, "k"} = HTTP.mint_key("w", "resident-r", expires)

    sent = Agent.get(agent, & &1)
    assert Enum.map(sent, &Recorded.refusal/1) == List.duplicate(nil, length(sent))

    assert sent == [
             %{method: "POST", path: ["workspaces"], params: %{}, body: %{"id" => "w"}},
             %{
               method: "POST",
               path: ["workspaces", "w", "peers"],
               params: %{},
               body: %{
                 "id" => "resident-r",
                 "configuration" => %{"custom_instructions" => "Be kind."}
               }
             },
             %{
               method: "PUT",
               path: ["workspaces", "w", "peers", "resident-r"],
               params: %{},
               body: %{"configuration" => %{"custom_instructions" => "Be kind."}}
             },
             %{
               method: "POST",
               path: ["workspaces", "w", "sessions"],
               params: %{},
               body: %{"id" => "s-1", "peers" => %{"witness-a" => %{}, "resident-r" => %{}}}
             },
             %{
               method: "POST",
               path: ["workspaces", "w", "sessions", "s-1", "messages"],
               params: %{},
               body: %{
                 "messages" => [
                   %{
                     "peer_id" => "witness-a",
                     "content" => "hi",
                     "created_at" => "2026-11-01T18:28:00.000000Z",
                     "metadata" => %{"turn_ref" => "t1"}
                   },
                   %{
                     "peer_id" => "resident-r",
                     "content" => "hello",
                     "created_at" => "2026-11-01T18:28:00.000000Z",
                     "metadata" => %{"turn_ref" => "t1"}
                   }
                 ]
               }
             },
             %{
               method: "POST",
               path: ["workspaces", "w", "sessions", "s-1", "messages", "list"],
               params: %{"page" => "1", "size" => "1"},
               body: %{"filters" => %{"metadata" => %{"turn_ref" => "t1"}}}
             },
             %{
               method: "PUT",
               path: ["workspaces", "w", "peers", "resident-r", "card"],
               params: %{},
               body: %{"peer_card" => ["Steady."]}
             },
             %{
               method: "GET",
               path: ["workspaces", "w", "peers", "resident-r", "card"],
               params: %{},
               body: nil
             },
             %{
               method: "GET",
               path: ["workspaces", "w", "peers", "resident-r", "card"],
               params: %{"target" => "witness-a"},
               body: nil
             },
             %{
               method: "GET",
               path: ["workspaces", "w", "peers", "resident-r", "context"],
               params: %{"target" => "witness-a"},
               body: nil
             },
             %{
               method: "POST",
               path: ["workspaces", "w", "conclusions", "list"],
               params: %{"page" => "1", "size" => "100"},
               body: %{
                 "filters" => %{"observer_id" => "resident-r", "observed_id" => "witness-a"}
               }
             },
             %{
               method: "POST",
               path: ["workspaces", "w", "conclusions", "list"],
               params: %{"page" => "2", "size" => "100"},
               body: %{
                 "filters" => %{"observer_id" => "resident-r", "observed_id" => "witness-a"}
               }
             },
             %{
               method: "DELETE",
               path: ["workspaces", "w", "conclusions", "c1"],
               params: %{},
               body: nil
             },
             %{
               method: "POST",
               path: ["keys"],
               params: %{
                 "workspace_id" => "w",
                 "peer_id" => "resident-r",
                 "expires_at" => "2026-11-02T18:28:00Z"
               },
               body: nil
             }
           ]
  end

  test "the names the client sent before are refused by the record, and by the in-memory Honcho as the 422 the bridge records" do
    for {read, why} <- @before, do: assert(Recorded.refusal(read) == why)

    old =
      @before
      |> Enum.at(3)
      |> elem(0)
      |> then(&%{method: :post, path: &1.path, params: [], body: &1.body})

    assert {:error, %Proteus.Error{kind: :proteus_honcho_rejected, details: details}} =
             Fake.wire(old)

    assert details[:status] == 422

    # The current spelling of the same message is taken.
    assert :ok =
             Fake.wire(
               Wire.messages("w", "s", [
                 %{peer: "p", content: "hi", created_at: ~U[2026-11-01 18:28:00Z], turn_ref: "t1"}
               ])
             )
  end

  test "an unconfigured Honcho is the bridge's sited error, not a raise inside the transport" do
    secret = Secret.wrap("test-honcho-secret")

    assert {:error,
            %Proteus.Error{
              kind: :proteus_honcho_unconfigured,
              details: [setting: "PROTEUS_HONCHO_URL"]
            }} =
             HTTP.configured(nil, nil, secret)

    assert {:error,
            %Proteus.Error{kind: :proteus_honcho_unconfigured, site: :proteus_http_key_unset}} =
             HTTP.configured("http://honcho:8000", Secret.wrap(nil), Secret.wrap(nil))

    assert {:ok, "http://honcho:8000", "set-key"} =
             HTTP.configured("http://honcho:8000", Secret.wrap("set-key"), secret)

    assert {:ok, "http://honcho:8000", minted} =
             HTTP.configured("http://honcho:8000", nil, secret)

    assert minted == HTTP.mint(secret)
  end

  test "a private service's host:port is read as http; a URL stays as given; anything else is refused" do
    assert Proteus.cast_url("honcho-api-x1y2:8000") == {:ok, "http://honcho-api-x1y2:8000"}
    assert Proteus.cast_url("http://honcho:8000") == {:ok, "http://honcho:8000"}

    assert Proteus.cast_url("https://honcho.example.invalid") ==
             {:ok, "https://honcho.example.invalid"}

    assert {:error, _} = Proteus.cast_url("honcho-api")
    assert {:error, _} = Proteus.cast_url("")
  end

  # The token below was computed outside this codebase, with Python's
  # hmac over the same bytes, and decoded by PyJWT (the library Honcho
  # verifies with) to {"ad": true, "t": ""} under the same secret.
  test "the admin key minted from the secret is the one Honcho's own create_admin_jwt would accept" do
    assert HTTP.mint(Secret.wrap("test-honcho-secret")) ==
             "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhZCI6dHJ1ZSwidCI6IiJ9.vhrkV6wdzg52pnot3Uv2l0cNK3467zlC7BiJRu7ff5Q"

    assert HTTP.mint(Secret.wrap(nil)) == nil
    assert HTTP.mint(nil) == nil
  end
end
