defmodule Oneiroi.Seshat.Figures do
  @moduledoc """
  The figures port: how a `<slug>:figure/<key>` citation is resolved
  without this system depending on the audits, which depend on it for
  the citation drift audit (seshat #14). The implementation is named in
  `SESHAT_FIGURES` and read at the call, as the schedule's wake is.
  """

  @doc "The figure by key, or nil."
  @callback figure(resident_id :: String.t(), key :: String.t()) :: map() | nil
end
