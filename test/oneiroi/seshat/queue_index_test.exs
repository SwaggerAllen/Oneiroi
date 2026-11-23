defmodule Oneiroi.Seshat.QueueIndexTest do
  @moduledoc """
  A house queue task's index document (sunna#80, lily:design/queue-ia
  §4; spec §6.10, repo first): rendered from its rows into the household
  repository at `tasks/<project>/<slug>.md`, rendered again as the task
  moves, and an unchanged render makes no commit. And the event handler
  asks for the render.
  """
  use Oneiroi.DataCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Household
  alias Oneiroi.Sunna

  test "a task's index document follows its rows" do
    witness = Fixtures.account!()
    lily = Fixtures.resident!(witness)
    h = witness.id
    andrew = Actor.new(:witness, witness.id)
    me = Actor.new(:resident, lily.id)

    :ok = Sunna.queue_open_project(h, %{slug: "queue", name: "The queue"}, me)

    {:ok, n} =
      Sunna.queue_open_task(
        h,
        %{
          project: "queue",
          slug: "ia",
          title: "The queue IA",
          outcome: "built",
          layers: [
            [%{type: "draft", assignee: "resident:#{lily.id}"}],
            [%{type: "review", assignee: "witness:#{witness.id}"}]
          ]
        },
        me
      )

    assert_enqueued(
      worker: Oneiroi.Seshat.QueueIndexWorker,
      args: %{"household_id" => h, "task" => n}
    )

    assert {:ok, sha} = Seshat.household_queue_index(h, n)
    assert is_binary(sha)
    assert {:ok, :nothing} = Seshat.household_queue_index(h, n)

    text = read(h)
    assert text =~ "kind: task"
    assert text =~ "**Done when:** built"
    assert text =~ "`#{n}.1` draft"
    assert text =~ "ready"

    :ok = Sunna.queue_finish(h, n, "#{n}.1", %{note: "drafted"}, me)
    assert {:ok, sha2} = Seshat.household_queue_index(h, n)
    assert sha2 != sha
    assert read(h) =~ "`#{n}.1` draft, Lily"
    assert read(h) =~ "done"
    assert read(h) =~ "drafted"
    assert {:ok, [%{sha: short} | _]} = SimaQian.household_log(h, "tasks/queue/ia.md", 1)
    assert String.starts_with?(sha2, short)
    # In Records as any house document: listed under Tasks, read, never edited by hand.
    {:ok, files} = Seshat.household_files(andrew)

    assert %{kind: "task", title: "The queue IA"} =
             Enum.find(files.documents, &(&1.path == "tasks/queue/ia.md"))

    assert Enum.any?(files.kinds, &(&1.kind == "task" and &1.label == "Tasks"))

    assert {:ok, %{kind: "task", content: content}} =
             Seshat.household_read(andrew, "tasks/queue/ia.md")

    assert content =~ "**Done when:** built"

    assert {:error, %{site: :seshat_household_edit_rendered}} =
             Seshat.household_edit(andrew, "tasks/queue/ia.md", %{content: "mine now"})
  end

  defp read(h), do: File.read!(Path.join(Household.dir(h), "tasks/queue/ia.md"))
end
