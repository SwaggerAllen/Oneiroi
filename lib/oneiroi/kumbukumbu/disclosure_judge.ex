defmodule Oneiroi.Kumbukumbu.DisclosureJudge do
  @moduledoc """
  The disclosure judge's port (kumbukumbu#82): asked, when a turn's
  ledger holds back a delivery, whether the candidate itself discloses
  what its turn held that the audience may not hear. It may refuse a
  delivery; it never grants one an explicit deny refused, and it never
  sees more than the candidate and the held-back fragments.

  A port because the judge is Eunomia's (a model of its own, never the
  resident's chat model), and Eunomia reads this system: a direct call
  would be the cycle. The implementation is named in
  `KUMBUKUMBU_DISCLOSURE_JUDGE` and read at the call: `eunomia` by
  default, her configured judge model (the witness's ruling,
  2026-11-20); `none`, a deployment with no judge, fails every review
  closed.
  """

  @type request :: %{
          candidate: String.t(),
          fragments: [%{ref: String.t(), text: String.t()}],
          audience: String.t()
        }
  # `quote`: the candidate's own words a DISCLOSES verdict points at
  # (kumbukumbu#104); a finding without one in the candidate is no finding.
  @type verdict :: %{
          verdict: :clean | :discloses,
          reasons: String.t(),
          quote: String.t() | nil,
          model: String.t()
        }

  @doc "The verdict on one candidate, or the failure: a failure ships nothing."
  @callback judge_disclosure(resident_id :: String.t(), request()) ::
              {:ok, verdict()} | {:error, term()}
end
