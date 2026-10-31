defmodule Oneiroi.Proteus.Honcho.HTTPTest do
  @moduledoc "The blueprint's wiring of Honcho (proteus #16): the address Render hands over, and the admin key minted from Honcho's own secret."
  use ExUnit.Case, async: true

  alias Oneiroi.Config.Secret
  alias Oneiroi.Proteus
  alias Oneiroi.Proteus.Honcho.HTTP

  test "a private service's host:port is read as http; a URL stays as given; anything else is refused" do
    assert Proteus.cast_url("honcho-api-x1y2:8000") == {:ok, "http://honcho-api-x1y2:8000"}
    assert Proteus.cast_url("http://honcho:8000") == {:ok, "http://honcho:8000"}

    assert Proteus.cast_url("https://honcho.example.invalid") ==
             {:ok, "https://honcho.example.invalid"}

    assert {:error, _} = Proteus.cast_url("honcho-api")
    assert {:error, _} = Proteus.cast_url("")
  end

  # The token below was computed outside this codebase, with Python's
  # hmac over the same bytes, and decoded by PyJWT (the library Honcho
  # verifies with) to {"ad": true, "t": ""} under the same secret.
  test "the admin key minted from the secret is the one Honcho's own create_admin_jwt would accept" do
    assert HTTP.mint(Secret.wrap("test-honcho-secret")) ==
             "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhZCI6dHJ1ZSwidCI6IiJ9.vhrkV6wdzg52pnot3Uv2l0cNK3467zlC7BiJRu7ff5Q"

    assert HTTP.mint(Secret.wrap(nil)) == nil
    assert HTTP.mint(nil) == nil
  end
end
