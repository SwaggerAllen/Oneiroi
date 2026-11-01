defmodule OneiroiWeb.ErrorJSONTest do
  @moduledoc "The body Phoenix answers with itself: the envelope, a request id, and nothing of the crash's message."
  use OneiroiWeb.ConnCase, async: true

  alias OneiroiWeb.ErrorJSON

  # On 2026-11-01 the first real import answered `{"errors": {"detail":
  # "Internal Server Error"}}` and the cause was found by reading the log
  # by timestamp. The crash's report held a clone URL with its token.

  test "a crash names its exception and request id, and not its message" do
    Logger.metadata(request_id: "GOPFcVhjQz0ptH4AAF1B")
    secret = "https://x-access-token:github_pat_TESTONLY@github.com/a/b.git"

    body =
      ErrorJSON.render("500.json", %{
        kind: :error,
        reason: %ErlangError{original: :enoent, reason: secret},
        stack: []
      })

    assert %{error: %{kind: "internal", request_id: "GOPFcVhjQz0ptH4AAF1B"} = error} = body
    assert error.meaning =~ "(ErlangError)"
    assert error.remedy =~ "GOPFcVhjQz0ptH4AAF1B"
    refute inspect(body) =~ "github_pat"
  end

  test "an uncaught exit says so" do
    body = ErrorJSON.render("500.json", %{kind: :exit, reason: :timeout, stack: []})
    assert body.error.meaning =~ "(an uncaught exit)"
  end

  test "a route nobody serves answers in the envelope, through the endpoint", %{conn: conn} do
    # Phoenix renders this one itself, through `render_errors`, so this is
    # the check that the endpoint is wired to this module at all.
    assert %{"error" => %{"kind" => "not_found", "meaning" => "Not Found", "request_id" => id}} =
             conn |> get("/v1/no-such-route") |> json_response(404)

    assert is_binary(id) and id != "unknown"
  end
end
