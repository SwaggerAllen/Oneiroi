defmodule Oneiroi.Gaia.Feedbacks do
  @moduledoc """
  Platform reports' service (gaia#20): filing, by a person or a resident;
  moving, by the operator or the triage resident; and the reads, each
  party's own and the operator's whole list.

  A report is the platform's to triage and the reporter's to follow:
  stored under the platform scope, read whole by the operator and the
  triage resident (`GAIA_TRIAGE_RESIDENT`, Lily), and by the reporter and
  their witness through `for_account/1`. The witness rail (`report_file`)
  is another system and never reaches here.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Door
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.FeedbackRouter
  alias Oneiroi.Gaia.PlatformRouter
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @doc "The stream's id, `feedback`; the suite gives each test its own (`Process.put(Oneiroi.Gaia.Feedbacks, id)`)."
  def stream, do: Process.get(__MODULE__, "feedback")

  @doc """
  Files a report: kind (bug or feature_request), surface (where, in the
  reporter's words), body, an optional trace id. A person files under
  their account; a resident under the witness's account beside its own.
  """
  def file(attrs, %Actor{} = actor) do
    {account, resident} = parties(actor)

    command = %Commands.FileFeedback{
      actor: actor,
      at: Clock.now(),
      id: stream(),
      kind: attrs[:kind],
      surface: attrs[:surface],
      body: attrs[:body],
      trace_id: attrs[:trace_id],
      account_id: account,
      resident_id: resident
    }

    case FeedbackRouter.dispatch(command) do
      {:ok, [event]} ->
        {:ok, event.number}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:gaia_dispatch_failed, :gaia_feedback_dispatch_failed, reason)}
    end
  end

  @doc "Moves a report's status, with a note: the operator's, or the triage resident's."
  def move(number, status, note, %Actor{} = actor) do
    with :ok <- may_move(actor) do
      command = %Commands.MoveFeedback{
        actor: actor,
        at: Clock.now(),
        id: stream(),
        number: number,
        status: status,
        note: note
      }

      case FeedbackRouter.dispatch(command) do
        {:ok, _} ->
          :ok

        {:error, %Error{}} = refused ->
          refused

        {:error, reason} ->
          {:error,
           Error.caught(:gaia_dispatch_failed, :gaia_feedback_move_dispatch_failed, reason)}
      end
    end
  end

  @doc "Every report, newest first, narrowed by kind and status."
  def list(filters \\ %{}) do
    stream = stream()

    Scope.platform(fn ->
      from(f in Store.Feedback, where: f.stream_key == ^stream, order_by: [desc: f.number])
      |> narrow(:kind, filters[:kind])
      |> narrow(:status, filters[:status])
      |> Repo.all()
    end)
  end

  @doc "One report, or nil."
  def get(number) do
    stream = stream()
    Scope.platform(fn -> Repo.get(Store.Feedback, "#{stream}:#{number}") end)
  end

  @doc "The reports an account filed or its residents did, newest first: what the reporter and their witness read."
  def for_account(account_id), do: Enum.filter(list(), &(&1.account_id == account_id))

  @doc "The reports a resident filed, newest first."
  def for_resident(resident_id),
    do: Enum.filter(list(), &(&1.resident_id == resident_id and &1.author_kind == "resident"))

  @doc "Whether the resident is the triage station."
  def triage?(resident_id), do: is_binary(resident_id) and resident_id == triage_resident()

  @doc """
  The triage resident's id, or nil when none is set or found: the desk
  as the operator set it (gaia#23), or, until it has ever been set,
  `GAIA_TRIAGE_RESIDENT`'s slug.
  """
  def triage_resident do
    with slug when is_binary(slug) and slug != "" <- triage_desk().slug,
         %{id: id} <- Enum.find(Oneiroi.AgathosDaimon.residents(), &(&1.slug == slug)) do
      id
    else
      _none -> nil
    end
  end

  @doc "The triage desk: its slug, where it came from, and who set it, when and why."
  def triage_desk do
    case Scope.platform(fn -> Repo.get(Store.Setting, "triage_resident") end) do
      %Store.Setting{} = s ->
        %{slug: s.value, from: "setting", note: s.note, set_by: s.set_by, set_at: s.set_at}

      nil ->
        case Config.fetch!(:gaia, :triage_resident) do
          slug when is_binary(slug) and slug != "" ->
            %{slug: slug, from: "environment", note: nil, set_by: nil, set_at: nil}

          _unset ->
            %{slug: nil, from: nil, note: nil, set_by: nil, set_at: nil}
        end
    end
  end

  @doc "Sets the triage desk to a resident's slug, or to nobody, with a note (gaia#23)."
  def set_triage_resident(slug, note, %Actor{} = actor) do
    slug = if is_binary(slug) and String.trim(slug) != "", do: String.trim(slug), else: nil

    if is_nil(slug) or Enum.any?(Oneiroi.AgathosDaimon.residents(), &(&1.slug == slug)) do
      command = %Commands.SetTriageResident{
        actor: actor,
        at: Clock.now(),
        id: Door.stream(),
        slug: slug,
        note: note
      }

      case PlatformRouter.dispatch(command) do
        {:ok, _events} ->
          :ok

        {:error, %Error{}} = refused ->
          refused

        {:error, reason} ->
          {:error, Error.caught(:gaia_dispatch_failed, :gaia_feedbacks_triage_dispatch, reason)}
      end
    else
      {:error, Error.new(:gaia_platform_invalid, :gaia_feedbacks_triage_no_resident, slug: slug)}
    end
  end

  defp narrow(query, _field, nil), do: query
  defp narrow(query, :kind, kind), do: from(f in query, where: f.kind == ^kind)
  defp narrow(query, :status, status), do: from(f in query, where: f.status == ^status)

  defp parties(%Actor{kind: :witness, id: id}), do: {id, nil}

  defp parties(%Actor{kind: :resident, id: id}) do
    case Oneiroi.AgathosDaimon.fetch(id) do
      {:ok, %{account_id: account}} -> {account, id}
      _none -> {nil, id}
    end
  end

  defp parties(_actor), do: {nil, nil}

  defp may_move(%Actor{kind: :witness, id: id}) do
    if Door.operator?(id),
      do: :ok,
      else: {:error, Error.new(:gaia_not_an_operator, :gaia_feedback_move_not_operator)}
  end

  defp may_move(%Actor{kind: :resident, id: id}) do
    if triage?(id),
      do: :ok,
      else: {:error, Error.new(:gaia_not_an_operator, :gaia_feedback_move_not_triage)}
  end

  defp may_move(%Actor{}),
    do: {:error, Error.new(:gaia_not_an_operator, :gaia_feedback_move_no_party)}
end
