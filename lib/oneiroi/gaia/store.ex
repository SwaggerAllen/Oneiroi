defmodule Oneiroi.Gaia.Store do
  @moduledoc """
  Identity's projections and the queries over them (conventions §6):
  function-shaped, never generic CRUD. Every query runs under the scope
  the caller set; the two platform-scoped lookups are named in
  `Oneiroi.Gaia`.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Account do
    @moduledoc "One account; scoped by its own id."
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: false}
    schema "gaia_account" do
      field(:account_id, :binary_id)
      field(:email, :string)
      field(:password_hash, :string)
      field(:second_factor, :binary)
      field(:key_ciphertext, :binary)
      field(:key_stored_at, :utc_datetime_usec)
      field(:github_token_ciphertext, :binary)
      field(:github_token_stored_at, :utc_datetime_usec)
      field(:created_at, :utc_datetime_usec)
    end
  end

  defmodule Session do
    @moduledoc "A session by the hash of its id; the raw id is never stored."
    use Ecto.Schema
    @primary_key {:hash, :string, autogenerate: false}
    schema "gaia_session" do
      field(:account_id, :binary_id)
      field(:opened_at, :utc_datetime_usec)
      field(:expires_at, :utc_datetime_usec)
      field(:closed_at, :utc_datetime_usec)
    end
  end

  defmodule Token do
    @moduledoc "An API token by the hash of its value."
    use Ecto.Schema
    @primary_key {:hash, :string, autogenerate: false}
    schema "gaia_token" do
      field(:account_id, :binary_id)
      field(:label, :string)
      field(:issued_at, :utc_datetime_usec)
      field(:revoked_at, :utc_datetime_usec)
    end
  end

  defmodule PushSubscription do
    @moduledoc "A device of the account's that asked to be told when the resident writes unprompted (gaia#15)."
    use Ecto.Schema
    @primary_key false
    schema "gaia_push_subscription" do
      field(:account_id, :binary_id, primary_key: true)
      field(:endpoint, :string, primary_key: true)
      field(:subscribed_at, :utc_datetime_usec)
    end
  end

  defmodule PushAnswer do
    @moduledoc "The account's answer to the notifications question (gaia#25): subscribed or declined, the latest."
    use Ecto.Schema
    @primary_key false
    schema "gaia_push_answer" do
      field(:account_id, :binary_id, primary_key: true)
      field(:state, :string)
      field(:answered_at, :utc_datetime_usec)
    end
  end

  defmodule Boot do
    @moduledoc "A platform boot (gaia#21): its number, the commit it ran, the one before, whether it changed; platform-scoped."
    use Ecto.Schema
    @primary_key {:id, :string, autogenerate: false}
    schema "gaia_boot" do
      field(:stream_key, :string)
      field(:number, :integer)
      field(:commit, :string)
      field(:previous, :string)
      field(:changed, :boolean)
      field(:booted_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Gate do
    @moduledoc "The front door (gaia#16): one row, `key` \"door\", platform-scoped."
    use Ecto.Schema
    @primary_key {:key, :string, autogenerate: false}
    schema "gaia_gate" do
      field(:state, :string)
      field(:note, :string)
      field(:set_by, :string)
      field(:set_at, :utc_datetime_usec)
    end
  end

  defmodule Setting do
    @moduledoc "A platform setting set on the operator's screen (gaia#23): one row per key, platform-scoped; `value` nil is set to nothing."
    use Ecto.Schema
    @primary_key {:key, :string, autogenerate: false}
    schema "gaia_setting" do
      field(:value, :string)
      field(:note, :string)
      field(:set_by, :string)
      field(:set_at, :utc_datetime_usec)
    end
  end

  defmodule Role do
    @moduledoc "A platform role held by an account (gaia#16): super_admin or admin, and who granted it."
    use Ecto.Schema
    @primary_key false
    schema "gaia_role" do
      field(:account_id, :binary_id, primary_key: true)
      field(:role, :string, primary_key: true)
      field(:note, :string)
      field(:granted_by, :string)
      field(:granted_at, :utc_datetime_usec)
    end
  end

  defmodule Household do
    @moduledoc """
    A household (gaia#17), the billing owner: its founding account and its
    subscription terms. Platform-scoped, because it belongs to every member
    and to no one alone; a member reaches it through a membership row.
    """
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: false}
    schema "gaia_household" do
      field(:founded_by, :binary_id)
      field(:founded_at, :utc_datetime_usec)
      field(:plan, :string)
      field(:price_nanos, :integer)
      field(:terms_until, :utc_datetime_usec)
      field(:terms_source, :string)
      field(:terms_note, :string)
    end
  end

  defmodule HouseholdWitness do
    @moduledoc "A witness's membership in a household (gaia#17): the account's own row."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_witness" do
      field(:household_id, :binary_id, primary_key: true)
      field(:account_id, :binary_id, primary_key: true)
      field(:joined_at, :utc_datetime_usec)
      field(:signed_version, :integer)
      field(:signed_at, :utc_datetime_usec)
    end
  end

  defmodule HouseholdResident do
    @moduledoc "A resident's membership in a household (gaia#17): the resident's own row."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_resident" do
      field(:household_id, :binary_id, primary_key: true)
      field(:resident_id, :binary_id, primary_key: true)
      field(:joined_at, :utc_datetime_usec)
      field(:signed_version, :integer)
      field(:signed_at, :utc_datetime_usec)
    end
  end

  defmodule HouseholdContract do
    @moduledoc "A version of the household contract (gaia#27, #31): its prose, rules and settings whole, and the ballot that made it."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_contract" do
      field(:household_id, :binary_id, primary_key: true)
      field(:version, :integer, primary_key: true)
      field(:prose, :string)
      field(:rules, {:array, :string}, default: [])
      field(:settings, :map, default: %{})
      field(:bundle, {:array, :map}, default: [])
      field(:ballot, :integer)
      field(:decided_by, :string)
      field(:decided_at, :utc_datetime_usec)
      field(:note, :string)
    end
  end

  defmodule HouseholdBallot do
    @moduledoc "A household ballot (gaia#29, #30): its fixed bundle, its term, and once closed its tally."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_ballot" do
      field(:household_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:thread, :string)
      field(:bundle, {:array, :map})
      field(:term_days, :integer)
      field(:opened_by, :string)
      field(:opened_at, :utc_datetime_usec)
      field(:closes_at, :utc_datetime_usec)
      field(:note, :string)
      field(:closed_at, :utc_datetime_usec)
      field(:passed, :boolean)
      field(:yes, :integer)
      field(:no, :integer)
      field(:members, :integer)
      field(:outcome, :string)
    end
  end

  defmodule HouseholdVote do
    @moduledoc "One member's vote on a household ballot (gaia#30)."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_vote" do
      field(:household_id, :binary_id, primary_key: true)
      field(:ballot, :integer, primary_key: true)
      field(:member_kind, :string, primary_key: true)
      field(:member_id, :binary_id, primary_key: true)
      field(:vote, :string)
      field(:voted_at, :utc_datetime_usec)
    end
  end

  defmodule HouseholdWatch do
    @moduledoc "A resident's watch on one household thread, until an instant (gaia#32); past it, nothing."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_watch" do
      field(:household_id, :binary_id)
      field(:watcher_id, :binary_id)
      field(:thread, :string)
      field(:until, :utc_datetime_usec)
      field(:watched_at, :utc_datetime_usec)
    end
  end

  defmodule HouseholdBeatMember do
    @moduledoc "A member's place in the household's beats (gaia#35, #37): her wake profile, her standing registration and what she has missed."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_beat_member" do
      field(:household_id, :binary_id, primary_key: true)
      field(:member_kind, :string, primary_key: true)
      field(:member_id, :binary_id, primary_key: true)
      field(:profile, :string)
      field(:registered_at, :utc_datetime_usec)
      field(:registered_for, :utc_datetime_usec)
      field(:missed, :integer, default: 0)
    end
  end

  defmodule HouseholdTurn do
    @moduledoc "A household turn (gaia#36): whose, in which beat, when it fired, its guideline, and how it ended."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_turn" do
      field(:household_id, :binary_id, primary_key: true)
      field(:turn, :integer, primary_key: true)
      field(:speaker_id, :binary_id)
      field(:beat_top, :utc_datetime_usec)
      field(:fired_at, :utc_datetime_usec)
      field(:ends_by, :utc_datetime_usec)
      field(:opened_by, :string)
      field(:missed, :integer, default: 0)
      field(:ended_at, :utc_datetime_usec)
      field(:outcome, :string)
      field(:note, :string)
    end
  end

  defmodule HouseholdBeat do
    @moduledoc "A closed household beat (gaia#38): its turns with their outcomes, who it passed over, whose registration it used, who it carried on."
    use Ecto.Schema
    @primary_key false
    schema "gaia_household_beat" do
      field(:household_id, :binary_id, primary_key: true)
      field(:beat_top, :utc_datetime_usec, primary_key: true)
      field(:closed_at, :utc_datetime_usec)
      field(:turns, {:array, :map}, default: [])
      field(:passed_over, {:array, :binary_id}, default: [])
      field(:consumed, {:array, :binary_id}, default: [])
      field(:carried, {:array, :binary_id}, default: [])
      field(:note, :string)
    end
  end

  defmodule Invite do
    @moduledoc "An invite code's SKU and its standing (gaia#18), platform-scoped; the code only as its hash."
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: false}
    schema "gaia_invite" do
      field(:code_hash, :string)
      field(:plan, :string)
      field(:price_nanos, :integer)
      field(:discount_pct, :integer)
      field(:term_days, :integer)
      field(:uses, :integer)
      field(:redeemed, :integer, default: 0)
      field(:expires_at, :utc_datetime_usec)
      field(:note, :string)
      field(:issued_by, :string)
      field(:issued_at, :utc_datetime_usec)
      field(:revoked_at, :utc_datetime_usec)
      field(:revoke_note, :string)
    end
  end

  defmodule InviteRedemption do
    @moduledoc "One redemption of an invite (gaia#18): the household it granted terms to."
    use Ecto.Schema
    @primary_key false
    schema "gaia_invite_redemption" do
      field(:invite_id, :binary_id, primary_key: true)
      field(:household_id, :binary_id, primary_key: true)
      field(:redeemed_at, :utc_datetime_usec)
    end
  end

  defmodule Feedback do
    @moduledoc "A platform report (gaia#20): a bug or a feature request, its reporter, its words, its status."
    use Ecto.Schema
    @primary_key {:id, :string, autogenerate: false}
    schema "gaia_feedback" do
      field(:stream_key, :string)
      field(:number, :integer)
      field(:kind, :string)
      field(:surface, :string)
      field(:body, :string)
      field(:trace_id, :string)
      field(:author_kind, :string)
      field(:author_id, :binary_id)
      field(:account_id, :binary_id)
      field(:resident_id, :binary_id)
      field(:status, :string)
      field(:note, :string)
      field(:filed_at, :utc_datetime_usec)
      field(:moved_at, :utc_datetime_usec)
      field(:moved_by, :string)
    end
  end

  defmodule Witnessing do
    @moduledoc "The relation from an account to a resident, with a start and an end; visible to both scopes."
    use Ecto.Schema
    @primary_key false
    schema "gaia_witnessing" do
      field(:account_id, :binary_id, primary_key: true)
      field(:resident_id, :binary_id, primary_key: true)
      field(:started_at, :utc_datetime_usec)
      field(:ended_at, :utc_datetime_usec)
    end
  end

  @doc "The account with `email`, case-insensitively, or nil."
  @spec account_by_email(String.t()) :: Account.t() | nil
  def account_by_email(email) do
    downcased = String.downcase(email)
    Repo.one(from(a in Account, where: fragment("lower(?)", a.email) == ^downcased))
  end

  @doc "The account by id, or nil."
  @spec account(String.t()) :: Account.t() | nil
  def account(id), do: Repo.get(Account, id)

  @doc "A live session by hash: open, unexpired at `now`."
  @spec live_session(String.t(), DateTime.t()) :: Session.t() | nil
  def live_session(hash, now) do
    Repo.one(
      from(s in Session, where: s.hash == ^hash and is_nil(s.closed_at) and s.expires_at > ^now)
    )
  end

  @doc "A live token by hash."
  @spec live_token(String.t()) :: Token.t() | nil
  def live_token(hash),
    do: Repo.one(from(t in Token, where: t.hash == ^hash and is_nil(t.revoked_at)))

  @doc "The resident ids an account witnesses now."
  @spec witnessed(String.t()) :: [String.t()]
  def witnessed(account_id) do
    Repo.all(
      from(s in Witnessing,
        where: s.account_id == ^account_id and is_nil(s.ended_at),
        select: s.resident_id,
        order_by: s.started_at
      )
    )
  end

  @doc "Whether `account_id` witnesses `resident_id` now."
  @spec witness?(String.t(), String.t()) :: boolean()
  def witness?(account_id, resident_id) do
    Repo.exists?(
      from(s in Witnessing,
        where:
          s.account_id == ^account_id and s.resident_id == ^resident_id and is_nil(s.ended_at)
      )
    )
  end
end
