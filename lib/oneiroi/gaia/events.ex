defmodule Oneiroi.Gaia.Events do
  @moduledoc "The account stream's events, version 1 (spec §3.1)."

  defmodule AccountCreated do
    use Oneiroi.Event, version: 1, fields: [:id, :email, :password_hash]
  end

  defmodule SecondFactorEnrolled do
    # The secret is the vault's ciphertext, base64: the log never holds it
    # in clear, and an export redacts even the ciphertext.
    use Oneiroi.Event, version: 1, fields: [:id, :secret_ciphertext], redact: [:secret_ciphertext]
  end

  defmodule SessionOpened do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :session_hash, :expires_at],
      instants: [:expires_at]
  end

  defmodule SessionClosed do
    use Oneiroi.Event, version: 1, fields: [:id, :session_hash]
  end

  defmodule TokenIssued do
    use Oneiroi.Event, version: 1, fields: [:id, :token_hash, :label]
  end

  defmodule TokenRevoked do
    use Oneiroi.Event, version: 1, fields: [:id, :token_hash]
  end

  defmodule KeyStored do
    # The witness's OpenRouter key (spec §6.11: one per witness, encrypted
    # at rest), the vault's ciphertext in base64; storing again is the
    # rotation. Redacted from the export like the second factor.
    use Oneiroi.Event, version: 1, fields: [:id, :key_ciphertext], redact: [:key_ciphertext]
  end

  defmodule KeyRevoked do
    use Oneiroi.Event, version: 1, fields: [:id]
  end

  defmodule GithubTokenStored do
    # The witness's GitHub read token (gaia#24): the resident's pull
    # request reads use it; the vault's ciphertext in base64, storing again
    # the rotation, redacted from the export as the key is.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :token_ciphertext],
      redact: [:token_ciphertext]
  end

  defmodule GithubTokenRevoked do
    use Oneiroi.Event, version: 1, fields: [:id]
  end

  defmodule WitnessingStarted do
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id]
  end

  defmodule WitnessingEnded do
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id]
  end

  defmodule PushSubscribed do
    # A device that will be told, content-free, when the resident writes
    # unprompted (gaia#15): its push service's endpoint, nothing else.
    use Oneiroi.Event, version: 1, fields: [:id, :endpoint]
  end

  defmodule PushUnsubscribed do
    # By the witness, or by the push service saying the device is gone.
    use Oneiroi.Event, version: 1, fields: [:id, :endpoint, :reason]
  end

  defmodule PushDeclined do
    # The witness's "No thanks" to the notifications question (gaia#25):
    # the account's answer, kept until a device subscribes, which is the
    # other answer. Nothing else is said.
    use Oneiroi.Event, version: 1, fields: [:id]
  end

  defmodule NeedsYouPushed do
    # The witness's devices were told that something waits on him
    # (gaia#26, brain#77): the resident and the needs-you entries the push
    # was for, each `%{"kind" => _, "ref" => _}`, its ref as a string. The
    # aggregate keeps every entry ever pushed, so none is pushed twice.
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id, :entries]
  end

  defmodule BootRecorded do
    # The platform started (gaia#21): numbered from 1, the commit it runs,
    # the one the boot before ran, and whether they differ. What restarted,
    # never why.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :commit, :previous, :changed]
  end

  defmodule GateSet do
    # The front door (gaia#16): closed, invite or open, by whom and why.
    use Oneiroi.Event, version: 1, fields: [:id, :state, :note]
  end

  defmodule TriageResidentSet do
    # The triage desk (gaia#23): the resident, by slug, who receives every
    # platform report as a letter and holds the triage tools; nil, nobody.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :slug]
  end

  defmodule RoleGranted do
    # A platform role (super_admin or admin) granted to an account, by
    # whom and why; the founding account's is granted by the platform.
    use Oneiroi.Event, version: 1, fields: [:id, :account_id, :role, :note]
  end

  defmodule RoleRevoked do
    use Oneiroi.Event, version: 1, fields: [:id, :account_id, :role, :note]
  end

  # The household (gaia#17), on `household-<id>`: the billing owner, with
  # its witnesses and its residents as memberships. Its id is the founding
  # account's, so an account's own household is found without a read.
  defmodule HouseholdFounded do
    use Oneiroi.Event, version: 1, fields: [:id, :account_id]
  end

  # Version 2 adds `signed_version` (gaia#28): the household contract's
  # version in force when the member joined, which joining signs; nil on
  # a version 1 membership and wherever no contract had been proposed.
  defmodule HouseholdWitnessJoined do
    use Oneiroi.Event, version: 2, fields: [:id, :account_id, :signed_version]
  end

  defimpl Commanded.Event.Upcaster, for: HouseholdWitnessJoined do
    def upcast(event, _metadata), do: event
  end

  defmodule HouseholdResidentJoined do
    use Oneiroi.Event, version: 2, fields: [:id, :resident_id, :signed_version]
  end

  defimpl Commanded.Event.Upcaster, for: HouseholdResidentJoined do
    def upcast(event, _metadata), do: event
  end

  defmodule HouseholdResidentLeft do
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id], decision: true
  end

  defmodule HouseholdTermsGranted do
    # The household's subscription terms: a plan and its price in
    # nano-dollars, good until an instant, and where they came from (an
    # invite code's id, or the operator). Nothing is charged.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :plan, :price_nanos, :terms_until, :source],
      instants: [:terms_until],
      decision: true
  end

  # The household contract (gaia#27, #28): versioned prose, rules and
  # settings, the dyad contract's pattern at the household's scale. The
  # founding witness proposes version 1, prose alone; it is in force at
  # once, and proposing it is the founder's signature.
  defmodule HouseholdContractProposed do
    use Oneiroi.Event, version: 1, fields: [:id, :version, :prose], decision: true
  end

  # A member's signature of the version in force, for a member who joined
  # before there was one; joining after signs on the membership itself.
  defmodule HouseholdContractSigned do
    use Oneiroi.Event, version: 1, fields: [:id, :member_kind, :member_id, :version]
  end

  # A ballot (gaia#29): a bundle of rules and settings fixed here, on the
  # thread whose trunk states it, with the term its proposer set.
  defmodule HouseholdBallotOpened do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :ballot, :thread, :bundle, :term_days, :closes_at],
      instants: [:closes_at],
      decision: true
  end

  # One vote a member, witness or resident, while the term runs (gaia#30).
  defmodule HouseholdBallotVoted do
    use Oneiroi.Event, version: 1, fields: [:id, :ballot, :member_kind, :member_id, :vote]
  end

  # The term closed: the tally over the members at the close, and whether
  # a majority of them carried the bundle (gaia#30).
  defmodule HouseholdBallotClosed do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :ballot, :passed, :yes, :no, :members],
      decision: true
  end

  # A ballot carried: the contract's next version, whole, with the bundle
  # it adds (gaia#31).
  defmodule HouseholdContractAmended do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :version, :ballot, :prose, :rules, :settings, :bundle],
      decision: true
  end

  # The watch (gaia#32): a resident opts in to one thread until an instant.
  defmodule HouseholdThreadWatched do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :resident_id, :thread, :until],
      instants: [:until]
  end

  # The beats (gaia#33 to #38). A member's wake profile, her own choice
  # (gaia#37).
  defmodule HouseholdWakeProfileSet do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :member_kind, :member_id, :profile],
      decision: true
  end

  # A resident enters the queue; `beat_top` is the beat she queues for
  # first, and the registration stands until a beat she had a turn in
  # closes (gaia#35).
  defmodule HouseholdBeatRegistered do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :resident_id, :beat_top],
      instants: [:beat_top]
  end

  # A turn opens: by the schedule (`opened_by` "schedule") or, for the dev
  # seed and the suite, by the platform's hand ("hand"); `missed` is what
  # she had missed when it fired (gaia#36).
  defmodule HouseholdTurnFired do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :turn, :resident_id, :beat_top, :ends_by, :missed, :opened_by],
      instants: [:beat_top, :ends_by]
  end

  # A turn ends: completed, declined, failed or timed_out; anything but
  # completed is an opportunity missed (gaia#36).
  defmodule HouseholdTurnEnded do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :turn, :resident_id, :beat_top, :outcome],
      instants: [:beat_top],
      decision: true
  end

  # A beat closes (gaia#38): its turns in order with their outcomes, the
  # registrants it passed over (each an opportunity missed), those whose
  # registration a completed turn used, and those carried to the next.
  defmodule HouseholdBeatClosed do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :beat_top, :turns, :passed_over, :consumed, :carried],
      instants: [:beat_top],
      decision: true
  end

  # An invite code (gaia#18), on `invite-<id>`: a SKU (plan, list price,
  # discount, how long the terms run, how many uses, until when), the
  # code itself never in the log, only its hash. Redeemed onto a
  # household; revoked with a note.
  defmodule InviteIssued do
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :code_hash,
        :plan,
        :price_nanos,
        :discount_pct,
        :term_days,
        :uses,
        :expires_at
      ],
      instants: [:expires_at],
      decision: true
  end

  defmodule InviteRedeemed do
    use Oneiroi.Event, version: 1, fields: [:id, :household_id]
  end

  defmodule InviteRevoked do
    use Oneiroi.Event, version: 1, fields: [:id], decision: true
  end

  # Platform reports (gaia#20), on the `feedback` stream: a bug or a
  # feature request from a person or a resident, in their words, for the
  # operator's triage and the triage resident. Never the witness rail
  # (report_file, Glitnir), which this does not touch.
  defmodule FeedbackFiled do
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :number,
        :kind,
        :surface,
        :body,
        :trace_id,
        :author_kind,
        :author_id,
        :account_id,
        :resident_id
      ]
  end

  defmodule FeedbackMoved do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :status], decision: true
  end
end
