defmodule Oneiroi.Seshat.Household.Core do
  @moduledoc """
  The member and the household, and provisioning (sima-qian#51,
  seshat#59): who is a member, who may post, a commit's author, and the
  repository made on first use with the thread kind's descriptor and
  `CONTRACT.md`.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.HouseholdRounds
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.SimaQian.Repos

  @platform %{name: "Oneiroi", email: "oneiroi@records.invalid"}
  @contract "CONTRACT.md"

  # ---- the member and the household ----

  @doc false
  def household(%Actor{} = actor) do
    with id when is_binary(id) <- Gaia.household_of(actor),
         true <- Gaia.household_member?(id, actor),
         # A resident with no agreement in force is not in the house yet
         # (agathos-daimon#51): no read, no write.
         false <- actor.kind == :resident and AgathosDaimon.held?(actor.id) do
      {:ok, id}
    else
      _none -> {:error, Error.new(:seshat_household_not_member, :seshat_household_no_membership)}
    end
  end

  @doc false
  def post_line, do: HouseholdRounds.post_line()

  @doc false
  # The household the actor is a member of, for the beats' own calls.
  def member_household(%Actor{} = actor), do: household(actor)

  @doc false
  # Every member posts: a witness takes part alongside the residents in
  # every way (the witness, 2026-11-11), unless a ballot has carried
  # `witnesses_post` false to bar the household's witnesses (seshat#69).
  def may_post(%Actor{kind: :resident}, _household_id), do: :ok

  def may_post(%Actor{kind: :witness}, household_id) do
    if Gaia.household_beat_shape(household_id).witnesses_post,
      do: :ok,
      else:
        {:error, Error.new(:seshat_household_residents_write, :seshat_household_witness_writes)}
  end

  def may_post(%Actor{}, _household_id),
    do: {:error, Error.new(:seshat_household_residents_write, :seshat_household_actor_writes)}

  @doc false
  # The commit's author: a resident by its name, a witness by whose
  # witness it is (gaia#27), never an email.
  def author(household_id, %Actor{kind: :resident, id: id} = actor) do
    slug =
      case AgathosDaimon.fetch(id) do
        {:ok, r} -> r.slug
        _gone -> id
      end

    %{
      name: Gaia.household_member_name(household_id, actor) || slug,
      email: "#{slug}@residents.oneiroi.invalid"
    }
  end

  def author(household_id, %Actor{kind: :witness, id: id} = actor),
    do: %{
      name: Gaia.household_member_name(household_id, actor) || "a witness",
      email: "#{id}@witnesses.oneiroi.invalid"
    }

  def author(_household_id, %Actor{}), do: @platform

  # ---- provisioning (sima-qian#51, seshat#59) ----

  @doc false
  def provision(household_id) do
    with {:ok, view} <- Files.view(household_id) do
      case descriptor(view, Kinds.named("thread")) ++ render_contract(view, household_id) do
        [] ->
          {:ok, view}

        changes ->
          # Two first readers may both write the descriptor; the second
          # finds it there, and reads the house again.
          _ =
            Repos.write(
              view.repo,
              changes,
              "Household: the shelf's kinds and its contract",
              @platform
            )

          Files.view(household_id)
      end
    end
  end

  @doc false
  # The kind's descriptor in its folder (seshat#51's `kind.json`): written
  # once, for a reader of the repository with no platform beside it.
  def descriptor(view, kind) do
    path = Path.join(kind.folder, Kinds.descriptor_name())

    if Files.has?(view, path) do
      []
    else
      body = %{
        "kind" => kind.kind,
        "folder" => kind.folder,
        "label" => kind[:label] || kind.kind,
        "layout" => kind.layout,
        "container" => Kinds.container?(kind),
        "cites" => kind.cites,
        "access" => "household",
        "written_by" => "residents, each under their own name; every member reads"
      }

      [{:create, path, Jason.encode_to_iodata!(body, pretty: true)}]
    end
  end

  @doc false
  def render_contract(view, household_id) do
    body = contract_text(Gaia.household_contract(household_id))

    if Files.file(view, @contract) == body,
      do: [],
      else: [{:put, @contract, body, Map.get(view.files, @contract)}]
  end

  defp contract_text(%{in_force: nil} = c) do
    """
    # The household contract

    No version yet: the founding witness proposes the first, prose alone.
    Rules and settings are added one ballot at a time.

    #{members_text(c.members)}
    """
  end

  defp contract_text(%{in_force: v} = c) do
    rules =
      case v.rules do
        [] -> "None yet: rules are added one ballot at a time."
        rules -> rules |> Enum.with_index(1) |> Enum.map_join("\n", fn {r, i} -> "#{i}. #{r}" end)
      end

    settings =
      case Enum.sort(v.settings) do
        [] -> "None yet."
        pairs -> Enum.map_join(pairs, "\n", fn {k, val} -> "- #{k}: #{inspect_value(val)}" end)
      end

    history =
      Enum.map_join(c.versions, "\n", fn h ->
        made = if h.ballot, do: "ballot ##{h.ballot}", else: "proposed by the founding witness"
        "- Version #{h.version}, #{Files.iso(h.decided_at)}, #{made}: #{h.note}"
      end)

    """
    # The household contract, version #{v.version}

    #{String.trim(v.prose)}

    ## Rules

    #{rules}

    ## Settings

    #{settings}

    ## Versions

    #{history}

    #{members_text(c.members)}
    """
  end

  defp members_text(members) do
    lines =
      Enum.map_join(members, "\n", fn m ->
        signed =
          if m.signed_version, do: "signed at version #{m.signed_version}", else: "not signed"

        "- #{m.name} (#{m.kind}), joined #{Files.iso(m.joined_at)}, #{signed}"
      end)

    "## Members\n\n" <> lines
  end

  @doc false
  def inspect_value(v) when is_binary(v), do: v

  def inspect_value(v), do: inspect(v)
end
