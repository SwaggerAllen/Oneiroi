defmodule Oneiroi.SimaQian.RemoteCheck do
  @moduledoc """
  The port that asks a backup remote's host what it is (sima-qian#65):
  whether the repository is private, and whether the token may push.
  Only GitHub answers today; `owner/repo` and the token in, and
  `{:ok, %{private: boolean, push: boolean | nil}}` or an error out:
  `sima_qian_remote_absent` (absent, or not visible to the token), else
  `sima_qian_remote_check_failed`.
  """

  @callback check(String.t(), term()) ::
              {:ok, %{private: boolean(), push: boolean() | nil}}
              | {:error, term()}
end
