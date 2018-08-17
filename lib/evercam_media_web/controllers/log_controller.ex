defmodule EvercamMediaWeb.LogController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  import EvercamMedia.Validation.Log
  import Ecto.Query
  alias EvercamMediaWeb.ErrorView
  alias EvercamMediaWeb.LogView
  import String, only: [to_integer: 1]

  @default_limit 50

  swagger_path :show do
    get "/cameras/{id}/logs"
    summary "Returns the logs."
    parameters do
      id :path, :string, "The ID of the camera being requested.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Cameras"
    response 200, "Success"
    response 401, "Invalid API keys"
    response 403, "Forbidden camera access"
    response 404, "Camera didn't found"
  end

  def show(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_edit(current_user, camera, conn),
         :ok <- validate_params(params) |> ensure_params(conn)
    do
      show_logs(params, camera, conn)
    end
  end

  def create(conn,  params) do
    current_user = conn.assigns[:current_user]

    with :ok <- authorized(conn, current_user),
         {:ok, camera} <- camera_exists(params["camera_exid"])
    do
      extra = %{
        browser: params["browser"],
        ip: user_request_ip(conn),
        version: params["version"],
        country: params["country"],
        country_code: params["country_code"]
      }
      CameraActivity.log_activity(current_user, camera, params["action"], extra)
      conn |> json(%{})
    end
  end

  def response_time(conn, %{"id" => exid}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_edit(current_user, camera, conn)
    do
      camera_response = ConCache.get(:camera_response_times, camera.exid)
      conn |> json(camera_response)
    end
  end

  defp ensure_camera_exists(nil, exid, conn) do
    conn
    |> put_status(404)
    |> render(ErrorView, "error.json", %{message: "Camera '#{exid}' not found!"})
  end
  defp ensure_camera_exists(_camera, _id, _conn), do: :ok

  defp ensure_can_edit(current_user, camera, conn) do
    if current_user && Permission.Camera.can_edit?(current_user, camera) do
      :ok
    else
      conn |> put_status(401) |> render(ErrorView, "error.json", %{message: "Unauthorized."})
    end
  end

  defp show_logs(params, camera, conn) do
    from = parse_from(params["from"])
    to = parse_to(params["to"])
    limit = parse_limit(params["limit"])
    page = parse_page(params["page"])
    types = parse_types(params["types"])

    all_logs =
      CameraActivity
      |> where(camera_id: ^camera.id)
      |> where([c], c.done_at >= ^from and c.done_at <= ^to)
      |> CameraActivity.with_types_if_specified(types)
      |> CameraActivity.get_all

    logs_count = Enum.count(all_logs)
    total_pages = Float.floor(logs_count / limit)
    logs = Enum.slice(all_logs, page * limit, limit)

    conn
    |> render(LogView, "show.json", %{total_pages: total_pages, camera_exid: camera.exid, camera_name: camera.name, logs: logs})
  end

  defp camera_exists(camera_exid) when camera_exid in [nil, ""] do
    {:ok, %{ id: 0, exid: "" }}
  end
  defp camera_exists(camera_exid) do
    case Camera.by_exid_with_associations(camera_exid) do
      nil -> {:ok, %{ id: 0, exid: "" }}
      %Camera{} = camera -> {:ok, camera}
    end
  end

  defp parse_to(to) when to in [nil, ""], do: Calendar.DateTime.now_utc |> Calendar.DateTime.to_erl
  defp parse_to(to), do: to |> Calendar.DateTime.Parse.unix! |> Calendar.DateTime.to_erl

  defp parse_from(from) when from in [nil, ""], do: Ecto.DateTime.cast!("2014-01-01T14:00:00Z") |> Ecto.DateTime.to_erl
  defp parse_from(from), do: from |> Calendar.DateTime.Parse.unix! |> Calendar.DateTime.to_erl

  defp parse_limit(limit) when limit in [nil, ""], do: @default_limit
  defp parse_limit(limit), do: if to_integer(limit) < 1, do: @default_limit, else: to_integer(limit)

  defp parse_page(page) when page in [nil, ""], do: 0
  defp parse_page(page), do: if to_integer(page) < 0, do: 0, else: to_integer(page)

  defp parse_types(types) when types in [nil, ""], do: nil
  defp parse_types(types), do: types |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp ensure_params(:ok, _conn), do: :ok
  defp ensure_params({:invalid, message}, conn), do: render_error(conn, 400, message)

  defp authorized(conn, nil), do: render_error(conn, 401, "Unauthorized.")
  defp authorized(_conn, _current_user), do: :ok
end
