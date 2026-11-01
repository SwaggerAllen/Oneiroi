defmodule Oneiroi.Ethos.LaneTest do
  @moduledoc "The trigger lane's vector index: refreshed on change alone, read beside the deterministic match, bounded, and silent when the provider fails."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Ethos
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake, as: Model

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    brain = Actor.new(:resident, resident.id, "fake/model")
    witness_actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", witness_actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, brain)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        resident.id,
        key,
        "t1",
        at,
        [%{role: :assistant, content: "The garden again.", sent_at: at, actor: brain}],
        brain
      )

    Model.clear()
    on_exit(fn -> Model.clear(for: resident.id) end)
    {:ok, id: resident.id, brain: brain, witness: witness_actor}
  end

  defp spent(id) do
    id
    |> Nisaba.budgets(:witness)
    |> Enum.find(&(&1.purpose == :embeddings))
    |> Map.fetch!(:spent_nanos)
  end

  test "the lane is refreshed on change alone, read beside the trigger match, bounded, and empty when the provider fails",
       ctx do
    id = ctx.id
    noon = ~U[2026-10-26 12:00:00Z]

    assert {:ok, %{embedded: 0, removed: 0}} = Ethos.refresh_lane(id, ctx.brain)

    # An empty lane answers empty with no model call.
    assert %{count: 0, near: []} =
             Ethos.how_i_act(id, %{
               text: "the garden is dry",
               tags: [],
               at: noon,
               actor: ctx.brain
             })

    assert %{spent_nanos: 0} =
             Enum.find(Nisaba.budgets(id, :witness), &(&1.purpose == :embeddings))

    {:ok, 1} =
      Ethos.define_habit(
        id,
        %{name: "waters the garden", trigger: %{"words" => ["hose"]}, stance: "keep"},
        ctx.witness
      )

    {:ok, 1} =
      Ethos.plant_seed(id, "I might be becoming someone who tends the garden.", ctx.brain)

    {:ok, 2} = Ethos.plant_seed(id, "I might be becoming quieter.", ctx.brain)

    # A read refreshes the lane itself: nearness, not the trigger, finds
    # the habit (no "hose" in the words, but the garden is), and the rows
    # are embedded on the way, so the explicit refresh after has nothing.
    assert %{count: 0, near: []} =
             Ethos.how_i_act(id, %{text: "the garden is dry", tags: [], at: noon})

    assert %{count: 1, numbers: [1], near: [1], near_seeds: [1], text: text} =
             Ethos.how_i_act(id, %{
               text: "the garden is dry",
               tags: [],
               at: noon,
               actor: ctx.brain
             })

    spent = spent(id)
    assert spent > 0
    assert {:ok, %{embedded: 0, removed: 0}} = Ethos.refresh_lane(id, ctx.brain)
    assert spent(id) == spent

    assert text =~ "#1 waters the garden (keep) (near this, by the lane)"
    assert text =~ "Near this: #1 I might be becoming someone who tends the garden."
    refute text =~ "quieter"

    # The trigger's own match is not marked as the lane's, and a word nothing shares finds nothing.
    assert %{count: 1, near: [], text: text} =
             Ethos.how_i_act(id, %{text: "the hose leaks", tags: [], at: noon, actor: ctx.brain})

    refute text =~ "near this, by the lane"

    assert %{count: 0, near_seeds: []} =
             Ethos.how_i_act(id, %{text: "hello", tags: [], at: noon, actor: ctx.brain})

    # A changed habit re-embeds its row alone; a wilted seed leaves the lane.
    :ok =
      Ethos.change_habit(
        id,
        1,
        %{name: "waters the roses", trigger: %{"words" => ["hose"]}, stance: "keep"},
        ctx.brain
      )

    assert {:ok, %{embedded: 1, removed: 0}} = Ethos.refresh_lane(id, ctx.brain)
    :ok = Ethos.wilt_seed(id, 2, ctx.brain)
    assert {:ok, %{embedded: 0, removed: 1}} = Ethos.refresh_lane(id, ctx.brain)

    # The provider failing leaves the deterministic match standing, and raises nothing.
    Model.embed_fail(:transport)

    assert %{count: 1, numbers: [1], near: []} =
             Ethos.how_i_act(id, %{text: "the hose leaks", tags: [], at: noon, actor: ctx.brain})

    :ok =
      Ethos.change_habit(
        id,
        1,
        %{name: "waters the tulips", trigger: %{"words" => ["hose"]}, stance: "keep"},
        ctx.brain
      )

    assert {:error, _} = Ethos.refresh_lane(id, ctx.brain)

    # A model answering another width fails the refresh rather than the table.
    Model.embed_width(3)

    assert {:error, %{kind: :ethos_embedding_mismatched, site: :ethos_lane_vector_width} = e} =
             Ethos.refresh_lane(id, ctx.brain)

    assert e.details == [width: 1536]
    Model.clear()
    assert {:ok, %{embedded: 1, removed: 0}} = Ethos.refresh_lane(id, ctx.brain)
  end
end
