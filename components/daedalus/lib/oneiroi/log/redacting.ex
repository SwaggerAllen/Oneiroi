defmodule Oneiroi.Log.Redacting do
  @moduledoc """
  The log handler's formatter, wrapping the real one: every line the
  handler writes is formatted as usual and then scrubbed of the
  credential shapes this platform handles, whatever path brought it
  there.

  It is the backstop, not the rule. The rule is that a credential is an
  `Oneiroi.Config.Secret` from the request onward and reaches a binary's
  arguments never (`Oneiroi.SimaQian.Git`). This exists because the rule
  is enforced one call site at a time and a crash report prints whatever
  its frame held: on 2026-11-01 a clone URL with Lily's read token went
  into the service log through `System.cmd`'s arguments, a path no
  `Logger` call wrote and no audit could see.

  Configured as `{#{inspect(__MODULE__)}, {inner, inner_config}}` on the
  default handler. The inner pair is passed through untouched, so prod
  keeps its tuple form for LoggerJSON (config/prod.exs says why a
  function call there fails the image build).

  The shapes are the ones in use here, each named for what produces it.
  A credential of a shape not listed passes through; this is a list of
  known shapes, not a guarantee, and widening it is a measured change.
  """

  @redacted "[REDACTED]"

  @patterns [
    # userinfo in any URL: a GitHub token rides there (plan decision 5),
    # and so does a database password.
    {~r<(://)[^/\s:@"']+:[^/\s@"']+@>, "\\1#{@redacted}@"},
    # GitHub fine-grained and classic tokens.
    {~r<github_pat_[A-Za-z0-9_]+>, @redacted},
    {~r<\bgh[pousr]_[A-Za-z0-9]{20,}>, @redacted},
    # OpenRouter keys, the witness's provider key (spec §6.11).
    {~r<\bsk-or-v1-[A-Za-z0-9]+>, @redacted},
    # A bearer or basic credential in a header someone logged.
    {~r<(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{16,}>, "\\1 #{@redacted}"}
  ]

  @doc "Formats `event` with the inner formatter, then redacts the line."
  @spec format(:logger.log_event(), {module(), term()}) :: String.t()
  def format(event, {formatter, config}) do
    event |> formatter.format(config) |> IO.iodata_to_binary() |> redact()
  end

  @doc "`text` with every known credential shape replaced."
  @spec redact(String.t()) :: String.t()
  def redact(text) when is_binary(text) do
    Enum.reduce(@patterns, text, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end
end
