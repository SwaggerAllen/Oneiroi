defmodule Oneiroi.Log.RedactingTest do
  @moduledoc "The log backstop: every credential shape in use is scrubbed, and ordinary text is not."
  use ExUnit.Case, async: true

  alias Oneiroi.Log.Redacting

  test "the crash report line from 2026-11-01, token and all" do
    line =
      ~s|System.cmd("git", ["clone", "-q", "--branch", "main", | <>
        ~s|"https://x-access-token:github_pat_11TESTONLY0abc_DEF@github.com/SwaggerAllen/Lily.git"])|

    redacted = Redacting.redact(line)
    refute redacted =~ "github_pat_"
    refute redacted =~ "11TESTONLY"
    assert redacted =~ "https://[REDACTED]@github.com/SwaggerAllen/Lily.git"
  end

  test "each shape alone" do
    for secret <- [
          "github_pat_11TESTONLY0abc_DEF",
          "ghp_TESTONLYTESTONLYTESTONLY1234",
          "sk-or-v1-0123456789abcdeftestonly",
          "postgres://oneiroi:hunter2pass@db.internal/oneiroi"
        ] do
      refute Redacting.redact("value: #{secret} end") =~ secret
    end

    assert Redacting.redact("Authorization: Bearer abcdefghijklmnop0123") ==
             "Authorization: Bearer [REDACTED]"
  end

  test "ordinary text passes through" do
    for text <- [
          "GET /v1/me",
          "https://github.com/SwaggerAllen/Lily.git",
          "user@example.org wrote 3 files",
          "a basic question"
        ] do
      assert Redacting.redact(text) == text
    end
  end

  test "it formats with the inner formatter first" do
    event = %{level: :error, msg: {:string, "token ghp_TESTONLYTESTONLYTESTONLY1234"}, meta: %{}}
    inner = Logger.Formatter.new(format: "$message\n")
    assert Redacting.format(event, inner) == "token [REDACTED]\n"
  end
end
