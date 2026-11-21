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
  `KUMBUKUMBU_DISCLOSURE_JUDGE` and read at the call; `none`, the
  default until the witness names the judge, fails every review closed.
  """

  @type request :: %{
          candidate: String.t(),
          fragments: [%{ref: String.t(), text: String.t()}],
          audience: String.t()
        }
  @type verdict :: %{verdict: :clean | :discloses, reasons: String.t(), model: String.t()}

  @doc "The verdict on one candidate, or the failure: a failure ships nothing."
  @callback judge_disclosure(resident_id :: String.t(), request()) ::
              {:ok, verdict()} | {:error, term()}
end
