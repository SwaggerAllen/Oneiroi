defmodule Oneiroi.Platform do
  @moduledoc """
  The platform system (spec §6.16): fleet pins, the configuration module,
  deploy, observability, the status page. In P0.1 it owns the one process
  the skeleton starts (PubSub), the two settings the endpoint needs, and
  the two audit checks that are Oneiroi's own rather than the substrate's:
  `gates` and `skips`. The Repo, Oban and the rest of the spine arrive
  with P0.2.
  """
  use Oneiroi.System, slug: :platform

  # Served over a network to people who are not its operator: `:service`,
  # under the core's own licence. `{:service, :listed}` arms no dependency
  # check, as it should; we offer source on AGPL's own terms.
  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      # Deliberately not PORT: this is the app's own listener, and
      # `render.yaml` sets both to one number so the platform's probe and
      # the app's socket cannot disagree. A bound, not a measurement.
      {:http_port, "PLATFORM_HTTP_PORT",
       cast: :integer,
       default: "8080",
       tag: :bound,
       usage: "the port the endpoint binds; the health probe reaches it directly"},
      # The endpoint's own secret: signs the session cookie. No default,
      # so a build without it fails at boot with the report naming it; the
      # cast enforces Plug.Session.Cookie's 64-byte floor so a short value
      # is a boot-time line rather than a 500 on the first request.
      {:secret_key_base, "PLATFORM_SECRET_KEY_BASE",
       cast: &__MODULE__.cast_secret_key_base/1,
       secret: true,
       usage: "signs the session cookie and every token the endpoint issues"}
    ]
  end

  @doc "Casts the endpoint secret, holding Plug.Session.Cookie's 64-byte floor."
  @spec cast_secret_key_base(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def cast_secret_key_base(raw) when byte_size(raw) >= 64, do: {:ok, raw}

  def cast_secret_key_base(raw) do
    # The byte count is not the secret; the value itself never appears.
    {:error, "must be at least 64 bytes (Plug.Session.Cookie's minimum), is #{byte_size(raw)}"}
  end

  @impl Oneiroi.Component
  def processes do
    [{:platform_pubsub, :local}]
  end

  @impl Oneiroi.Component
  def policies do
    [
      {Oneiroi.Platform.Policies.Gates, "pipeline.config.json",
       policy: "conventions §2: the gate set is identical in CLAUDE.md, ci.yml and qualityGates"},
      {Oneiroi.Platform.Policies.Skips, "test/**/*.exs",
       policy: "conventions §9: a skipped test names the ticket that owns it"}
    ]
  end

  @impl Oneiroi.Component
  def children do
    [{Phoenix.PubSub, name: :platform_pubsub}]
  end
end
