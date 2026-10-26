defmodule OneiroiWeb.Router do
  use OneiroiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # `/v1` is the JSON API (spec §2); identity (P0.4) adds its first routes.
  scope "/v1", OneiroiWeb do
    pipe_through :api
  end
end
