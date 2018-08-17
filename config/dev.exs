use Mix.Config

config :evercam_media,
  start_camera_workers: System.get_env["START_CAMERA_WORKERS"]

config :evercam_media,
  start_evercam_bot: false

config :evercam_media,
  start_timelapse_workers: false

# For development, we disable any cache and enable
# debugging and code reloading.
config :evercam_media, EvercamMediaWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  cache_static_lookup: false,
  email: "Evercam <env.dev@evercam.io>"

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Do not create intercom user in development mode
config :evercam_media, :create_intercom_user, false

# Start spawn process or not
config :evercam_media, :run_spawn, true

# Set a higher stacktrace during development.
# Do not configure such in production as keeping
# and calculating stacktraces is usually expensive.
config :phoenix, :stacktrace_depth, 20

# Configure your database
config :evercam_media, EvercamMedia.Repo,
  adapter: Ecto.Adapters.Postgres,
  types: EvercamMedia.PostgresTypes,
  username: "postgres",
  password: "postgres",
  database: System.get_env["db"] || "evercam_dev"

config :evercam_media, EvercamMedia.SnapshotRepo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: System.get_env["db"] || "evercam_dev"
