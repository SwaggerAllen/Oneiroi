defmodule OneiroiWeb.ApiSpec do
  @moduledoc "The OpenAPI document the client generates from (spec §2.1): derived from the router, served at /v1/openapi.json."
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Info, OpenApi, Paths}

  # No `servers`: paths resolve relative to the document's own URL, which
  # is the one the client fetched it from, and naming the endpoint here
  # closed a cycle (the endpoint mounts this document).
  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      info: %Info{title: "Oneiroi", version: "0.1.0"},
      paths: Paths.from_router(OneiroiWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
