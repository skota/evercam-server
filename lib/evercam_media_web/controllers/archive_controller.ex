defmodule EvercamMediaWeb.ArchiveController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMediaWeb.ArchiveView
  alias EvercamMedia.Util
  alias EvercamMedia.Snapshot.Storage
  import Ecto.Changeset
  import EvercamMedia.TimelapseRecording.S3, only: [load_compare_thumbnail: 2, do_load: 1, get_presigned_url_to_object: 1]
  require Logger

  @status %{pending: 0, processing: 1, completed: 2, failed: 3}

  def swagger_definitions do
    %{
      Archive: swagger_schema do
        title "Archive"
        description ""
        properties do
          id :integer, ""
          camera_id :integer, ""
          exid :string, "", format: "text"
          title :string, "", format: "text"
          from_date :string, "", format: "timestamp"
          to_date :string, "", format: "timestamp"
          status :integer, ""
          requested_by :integer, ""
          embed_time :boolean, ""
          public :boolean, ""
          frames :integer, ""
          url :string, "", format: "character(255)"
          file_name :string, "", format: "character(255)"
          created_at :string, "", format: "timestamp"
        end
      end
    }
  end

  swagger_path :index do
    get "/cameras/{id}/archives"
    summary "Returns the archives list of given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 403, "Camera does not exist"
  end

  def index(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)
    status = params["status"]

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      archives =
        Archive
        |> Archive.by_camera_id(camera.id)
        |> Archive.with_status_if_given(status)
        |> Archive.get_all_with_associations

      compare_archives = Compare.get_by_camera(camera.id)

      render(conn, ArchiveView, "index.json", %{archives: archives, compares: compare_archives})
    end
  end

  swagger_path :show do
    get "/cameras/{id}/archives/{archive_id}"
    summary "Returns the archives Details."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist or Archive does not found"
  end

  def show(conn, %{"id" => exid, "archive_id" => archive_id} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- valid_params(conn, params),
         :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- deliver_content(conn, exid, archive_id),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      archive = Archive.by_exid(archive_id)

      case archive do
        nil ->
          render_error(conn, 404, "Archive '#{archive_id}' not found!")
        _ ->
          render(conn, ArchiveView, "show.json", %{archive: archive})
      end
    end
  end

  swagger_path :play do
    get "/cameras/{id}/archives/{archive_id}/play"
    summary "Play the requested archive of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist or Archive does not found"
  end

  def play(conn, %{"id" => exid, "archive_id" => archive_id}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_can_list(current_user, camera, conn) do
      {:ok, url} = get_presigned_url_to_object("#{exid}/clips/#{archive_id}/#{archive_id}.mp4")
      conn
      |> redirect(external: url)
    end
  end

  swagger_path :thumbnail do
    get "/cameras/{id}/archives/{archive_id}/thumbnail"
    summary "Returns the jpeg thumbnail of given archive."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      type :query, :string, "Media type of archive.", required: true, enum: ["clip", "compare", "others"]
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys"
  end

  def thumbnail(conn, %{"id" => exid, "archive_id" => archive_id, "type" => media_type}) do
    data =
      case media_type do
        "clip" -> Storage.load_archive_thumbnail(exid, archive_id)
        "compare" -> load_compare_thumbnail(exid, archive_id)
        _ -> Util.default_thumbnail
      end
    conn
    |> put_resp_header("content-type", "image/jpeg")
    |> text(data)
  end

  swagger_path :create do
    post "/cameras/{id}/archives"
    summary "Create new archive."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      title :query, :string, "Name of the clip.", required: true
      from_date :query, :string, "Unix timestamp", required: true
      to_date :query, :string, "Unix timestamp", required: true
      is_nvr_archive :query, :boolean, ""
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 400, "Bad Request"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist"
  end

  def create(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      create_clip(params, camera, conn, current_user, params["type"])
    end
  end

  swagger_path :update do
    patch "/cameras/{id}/archives/{archive_id}"
    summary "Updates full or partial data for an existing archive."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      title :query, :string, ""
      status :query, :string, "",enum: ["pending","processing","completed","failed"]
      public :query, :boolean, ""
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 400, "Bad Request"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist"
  end

  def update(conn, %{"id" => exid, "archive_id" => archive_id} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- valid_params(conn, params),
         :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      update_clip(conn, camera, params, archive_id)
    end
  end

  swagger_path :pending_archives do
    get "/cameras/archives/pending"
    summary "Returns all pending archives."
    parameters do
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
  end

  def pending_archives(conn, _) do
    requester = conn.assigns[:current_user]

    if requester do
      archive =
        Archive
        |> Archive.with_status_if_given(@status.pending)
        |> Archive.get_one_with_associations

      conn
      |> render(ArchiveView, "show.json", %{archive: archive})
    else
      render_error(conn, 401, "Unauthorized.")
    end
  end

  swagger_path :delete do
    delete "/cameras/{id}/archives/{archive_id}"
    summary "Delete the archives for given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist"
  end

  def delete(conn, %{"id" => exid, "archive_id" => archive_id}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         {:ok, archive} <- archive_exists(conn, archive_id),
         :ok <- ensure_can_delete(current_user, camera, conn, archive.user.username)
    do
      Archive.delete_by_exid(archive_id)
      spawn(fn -> Storage.delete_archive(camera.exid, archive_id) end)
      CameraActivity.log_activity(current_user, camera, "archive deleted", %{name: archive.title, ip: user_request_ip(conn)})
      json(conn, %{})
    end
  end

  defp create_clip(params, camera, conn, current_user, "url") do
    changeset = archive_changeset(params, camera, current_user, @status.completed)
    case Repo.insert(changeset) do
      {:ok, archive} ->
        archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
        CameraActivity.log_activity(current_user, camera, "saved media URL", %{ip: user_request_ip(conn)})
        render(conn |> put_status(:created), ArchiveView, "show.json", %{archive: archive})
      {:error, changeset} ->
        render_error(conn, 400, Util.parse_changeset(changeset))
    end
  end
  defp create_clip(params, camera, conn, current_user, "file") do
    changeset = archive_changeset(params, camera, current_user, @status.completed)
    exid = get_field(changeset, :exid)
    changeset = put_change(changeset, :file_name, "#{exid}.#{params["file_extension"]}")

    case Repo.insert(changeset) do
      {:ok, archive} ->
        archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
        CameraActivity.log_activity(current_user, camera, "file uploaded", %{ip: user_request_ip(conn)})
        copy_uploaded_file(Application.get_env(:evercam_media, :run_spawn), camera.exid, archive.exid, params["file_url"], params["file_extension"])
        render(conn |> put_status(:created), ArchiveView, "show.json", %{archive: archive})
      {:error, changeset} ->
        render_error(conn, 400, Util.parse_changeset(changeset))
    end
  end
  defp create_clip(params, camera, conn, current_user, _type) do
    timezone = camera |> Camera.get_timezone
    unix_from = params["from_date"]
    unix_to = params["to_date"]
    from_date = clip_date(unix_from, timezone)
    to_date = clip_date(unix_to, timezone)

    changeset = archive_changeset(params, camera, current_user, @status.pending)

    current_date_time =
      Calendar.DateTime.now_utc
      |> Calendar.DateTime.to_erl

    cond do
      !changeset.valid? ->
        render_error(conn, 400, Util.parse_changeset(changeset))
      to_date < from_date ->
        render_error(conn, 400, "To date cannot be less than from date.")
      current_date_time <= from_date ->
        render_error(conn, 400, "From date cannot be greater than current time.")
      current_date_time <= to_date ->
        render_error(conn, 400, "To date cannot be greater than current time.")
      to_date == from_date ->
        render_error(conn, 400, "To date and from date cannot be same.")
      date_difference(from_date, to_date) > 3600 ->
        render_error(conn, 400, "Clip duration cannot be greater than 60 minutes.")
      true ->
        case Repo.insert(changeset) do
          {:ok, archive} ->
            archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
            CameraActivity.log_activity(current_user, camera, "archive created", %{ip: user_request_ip(conn)})
            start_archive_creation(Application.get_env(:evercam_media, :run_spawn), camera, archive, unix_from, unix_to, params["is_nvr_archive"])
            render(conn |> put_status(:created), ArchiveView, "show.json", %{archive: archive})
          {:error, changeset} ->
            render_error(conn, 400, Util.parse_changeset(changeset))
        end
    end
  end

  defp archive_changeset(params, camera, current_user, status) do
    timezone = camera |> Camera.get_timezone
    unix_from = params["from_date"]
    unix_to = params["to_date"]
    from_date = clip_date(unix_from, timezone)
    to_date = clip_date(unix_to, timezone)
    clip_exid = generate_exid(params["title"])

    archive_params =
      params
      |> Map.delete("id")
      |> Map.delete("api_id")
      |> Map.delete("api_key")
      |> Map.merge(%{
        "requested_by" => current_user.id,
        "camera_id" => camera.id,
        "title" => params["title"],
        "from_date" => from_date,
        "to_date" => to_date,
        "status" => status,
        "exid" => clip_exid,
        "url" => params["url"]
      })
    Archive.changeset(%Archive{}, archive_params)
  end

  defp update_clip(conn, _camera, params, archive_id) do
    case Archive.by_exid(archive_id) do
      nil ->
        render_error(conn, 404, "Archive '#{archive_id}' not found!")
      archive ->
        archive_params =
          %{}
          |> add_parameter("field", "status", params["status"])
          |> add_parameter("field", "title", params["title"])
          |> add_parameter("field", "public", params["public"])
          |> add_parameter("field", "url", params["url"])


        changeset = Archive.changeset(archive, archive_params)
        case Repo.update(changeset) do
          {:ok, archive} ->
            updated_archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
            render(conn, ArchiveView, "show.json", %{archive: updated_archive})
          {:error, changeset} ->
            render_error(conn, 400, Util.parse_changeset(changeset))
        end
    end
  end

  defp add_parameter(params, _field, _key, nil), do: params
  defp add_parameter(params, "field", key, value) do
    Map.put(params, key, value)
  end

  defp start_archive_creation(true, camera, archive, unix_from, unix_to, is_nvr) when is_nvr in [true, "true"] do
    spawn fn ->
      EvercamMedia.HikvisionNVR.extract_clip_from_stream(camera, archive, convert_timestamp(unix_from), convert_timestamp(unix_to))
    end
  end
  defp start_archive_creation(true, _camera, archive, _unix_from, _unix_to, _is_nvr) do
    spawn fn ->
      case Process.whereis(:archive_creator) do
        nil ->
          {:ok, pid} = GenStage.start_link(EvercamMedia.ArchiveCreator.ArchiveCreator, {}, name: :archive_creator)
          GenStage.cast(pid, {:create_archive, archive.exid})
        pid ->
          GenStage.cast(pid, {:create_archive, archive.exid})
      end
    end
  end
  defp start_archive_creation(_mode, _camera, _archive, _unix_from, _unix_to, _is_nvr), do: :noop

  defp copy_uploaded_file(true, camera_id, archive_id, url, extension) do
    spawn fn ->
      Storage.save_archive_file(camera_id, archive_id, url, extension)
      create_thumbnail(camera_id, archive_id, extension)
    end
  end
  defp copy_uploaded_file(_mode, _camera_id, _archive_id, _url, _extension), do: :noop

  defp create_thumbnail(camera_id, archive_id, extension) do
    root_dir = "#{Application.get_env(:evercam_media, :storage_dir)}/#{archive_id}/"
    file_path = "#{root_dir}#{archive_id}.#{extension}"
    case Porcelain.shell("convert -thumbnail 640x480 -background white -alpha remove \"#{file_path}\"[0] #{root_dir}thumb-#{archive_id}.jpg", [err: :out]).out do
      "" -> :noop
      _ -> Porcelain.shell("ffmpeg -i #{file_path} -vframes 1 -vf scale=640:-1 -y #{root_dir}thumb-#{archive_id}.jpg", [err: :out]).out
    end
    Storage.save_archive_thumbnail(camera_id, archive_id, root_dir)
    File.rm_rf(root_dir)
  end

  defp convert_timestamp(timestamp) do
    timestamp
    |> String.to_integer
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("%Y%m%dT%H%M%SZ")
  end

  defp ensure_camera_exists(nil, exid, conn) do
    render_error(conn, 404, "Camera '#{exid}' not found!")
  end
  defp ensure_camera_exists(_camera, _exid, _conn), do: :ok

  defp ensure_can_list(current_user, camera, conn) do
    if current_user && Permission.Camera.can_list?(current_user, camera) do
      :ok
    else
      render_error(conn, 401, "Unauthorized.")
    end
  end

  defp valid_params(conn, params) do
    if present?(params["id"]) && present?(params["archive_id"]) do
      :ok
    else
      render_error(conn, 400, "Parameters are invalid!")
    end
  end

  defp present?(param) when param in [nil, ""], do: false
  defp present?(_param), do: true

  defp archive_exists(conn, archive_id) do
    case Archive.by_exid(archive_id) do
      nil -> render_error(conn, 404, "Archive '#{archive_id}' not found!")
      %Archive{} = archive -> {:ok, archive}
    end
  end

  defp ensure_can_delete(nil, _camera, conn, _requester), do: render_error(conn, 401, "Unauthorized.")
  defp ensure_can_delete(current_user, camera, conn, requester) do
    case Permission.Camera.can_edit?(current_user, camera) do
      true -> :ok
      false ->
        case current_user.username do
          username when username == requester -> :ok
          _ -> render_error(conn, 403, "Unauthorized.")
        end
    end
  end

  defp clip_date(unix_timestamp, _timezone) when unix_timestamp in ["", nil], do: nil
  defp clip_date(unix_timestamp, "Etc/UTC") do
    unix_timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.DateTime.to_erl
  end
  defp clip_date(unix_timestamp, timezone) do
    unix_timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.DateTime.to_erl
    |> Calendar.DateTime.from_erl!(timezone)
    |> Calendar.DateTime.shift_zone!("Etc/UTC")
    |> Calendar.DateTime.to_erl
  end

  defp date_difference(from_date, to_date) do
    from = Calendar.DateTime.from_erl!(to_date, "Etc/UTC")
    to = Calendar.DateTime.from_erl!(from_date, "Etc/UTC")
    case Calendar.DateTime.diff(from, to) do
      {:ok, seconds, _, :after} -> seconds
      _ -> 1
    end
  end

  defp generate_exid(title) when title in ["", nil], do: nil
  defp generate_exid(title) do
    clip_exid =
      title
      |> Util.slugify
      |> String.replace(~r/\W/, "")
      |> String.downcase
      |> String.slice(0..5)

    random_string = Enum.concat(?a..?z, ?0..?9) |> Enum.take_random(4)
    "#{clip_exid}-#{random_string}"
  end

  defp deliver_content(conn, exid, archive_id) do
    archive_with_extension = String.split(archive_id, ".")
    case length(archive_with_extension) do
      2 ->
        [file_name, extension] = archive_with_extension
        ensure_is_public(conn, file_name)
        |> load_file(conn, exid, file_name, extension)
      _ -> :ok
    end
  end

  defp ensure_is_public(conn, archive_exid) do
    with {:ok, archive} <- archive_exists(conn, archive_exid) do
      case archive.public do
        true -> :public
        _ -> :private
      end
    end
  end

  defp load_file(:private, conn, _camera_exid, file_name, _extension), do: render_error(conn, 404, "Archive '#{file_name}' not public!")
  defp load_file(:public, conn, camera_exid, file_name, extension) do
    {:ok, response} = do_load("#{camera_exid}/clips/#{file_name}/#{file_name}.#{extension}")
    conn
    |> put_resp_header("content-type", "video/mp4")
    |> text(response)
  end
end
