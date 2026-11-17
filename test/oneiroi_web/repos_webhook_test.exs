defmodule OneiroiWeb.ReposWebhookTest do
  @moduledoc """
  Gitea's push webhook (sima-qian#59): a push from outside into a
  resident's repository, signed with the webhook's secret, asks for her
  index run; the core's own writes, the household's repository, another
  branch and a stranger's repository ask for nothing; an unsigned push
  is refused, and with no secret set the webhook is off.
  """
  use OneiroiWeb.ConnCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.IndexWorker
  alias Oneiroi.SimaQian.Gitea

  @secret "gitea_test_suite"
  @store {Oneiroi.Config, :values}

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    andrew = Actor.new(:witness, account.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    resident = Fixtures.resident!(account)
    org = Gitea.org(Gaia.household_id(account.id))
    {:ok, resident: resident, org: org}
  end

  defp pushed(org, name, opts \\ []) do
    body =
      Jason.encode!(%{
        ref: Keyword.get(opts, :ref, "refs/heads/main"),
        pusher: %{login: Keyword.get(opts, :pusher, "w-0123456789ab")},
        repository: %{name: name, owner: %{login: org}}
      })

    sig =
      Keyword.get_lazy(opts, :signature, fn ->
        :crypto.mac(:hmac, :sha256, @secret, body) |> Base.encode16(case: :lower)
      end)

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> then(&if(sig, do: put_req_header(&1, "x-gitea-signature", sig), else: &1))
    |> post("/v1/repos/gitea", body)
  end

  defp jobs, do: for(j <- all_enqueued(worker: IndexWorker), do: j.args["resident_id"])

  test "a push from outside into her repository asks for her index run, once while it waits",
       ctx do
    assert %{"indexing" => true} = json_response(pushed(ctx.org, ctx.resident.slug), 200)
    assert %{"indexing" => true} = json_response(pushed(ctx.org, ctx.resident.slug), 200)
    assert jobs() == [ctx.resident.id]
  end

  test "the core's own writes, the household's repository, another branch and a stranger's ask for nothing",
       ctx do
    for conn <- [
          pushed(ctx.org, ctx.resident.slug, pusher: "oneiroi-admin"),
          pushed(ctx.org, "house"),
          pushed(ctx.org, ctx.resident.slug, ref: "refs/heads/draft"),
          pushed("h-000000000000", ctx.resident.slug),
          pushed(ctx.org, "nobody-here")
        ],
        do: assert(%{"indexing" => false} = json_response(conn, 200))

    assert jobs() == []
  end

  test "unsigned or signed with another secret: refused", ctx do
    assert json_response(pushed(ctx.org, ctx.resident.slug, signature: nil), 400)

    assert json_response(
             pushed(ctx.org, ctx.resident.slug, signature: String.duplicate("0", 64)),
             400
           )

    assert jobs() == []
  end

  test "no secret set: the webhook is off", ctx do
    values = :persistent_term.get(@store)
    on_exit(fn -> :persistent_term.put(@store, values) end)
    :persistent_term.put(@store, Map.put(values, {:sima_qian, :gitea_webhook_secret}, nil))

    assert json_response(pushed(ctx.org, ctx.resident.slug), 503)
  end
end
