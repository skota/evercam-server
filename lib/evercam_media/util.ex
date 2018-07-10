defmodule EvercamMedia.Util do
  require Logger
  import String, only: [to_integer: 1]

  def deep_get(map, keys, default \\ nil), do: do_deep_get(map, keys, default)

  defp do_deep_get(nil, _, default), do: default
  defp do_deep_get(%{} = map, [], default) when map_size(map) == 0, do: default
  defp do_deep_get(value, [], _default), do: value
  defp do_deep_get(map, [key|rest], default) do
    map
    |> Map.get(key, %{})
    |> do_deep_get(rest, default)
  end

  def unavailable do
    ConCache.dirty_get_or_store(:snapshot_error, "unavailable", fn() ->
      Application.app_dir(:evercam_media)
      |> Path.join("priv/static/images/unavailable.jpg")
      |> File.read!
    end)
  end

  def default_thumbnail do
    ConCache.dirty_get_or_store(:snapshot_error, "default_thumbnail", fn() ->
      Application.app_dir(:evercam_media)
      |> Path.join("priv/static/images/default-thumbnail.jpg")
      |> File.read!
    end)
  end

  def storage_unavailable do
    ConCache.dirty_get_or_store(:snapshot_error, "storage_unavailable", fn() ->
      Application.app_dir(:evercam_media)
      |> Path.join("priv/static/images/storage-unavailable.jpg")
      |> File.read!
    end)
  end

  def jpeg?(<<0xFF, 0xD8, _ :: binary>>), do: true
  def jpeg?(_), do: false

  def port_open?(address, port) do
    case :gen_tcp.connect(to_charlist(address), to_integer(port), [:binary, active: false], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true
      {:error, _error} ->
        false
    end
  end

  def encode(args) do
    message = format_token_message(args)
    encrypted_message = :crypto.block_encrypt(
      :aes_cbc256,
      System.get_env["SNAP_KEY"],
      System.get_env["SNAP_IV"],
      message)
    Base.url_encode64(encrypted_message)
  end

  def decode(token) do
    encrypted_message = Base.url_decode64!(token)
    message = :crypto.block_decrypt(
      :aes_cbc256,
      System.get_env["SNAP_KEY"],
      System.get_env["SNAP_IV"],
      encrypted_message)
    message |> String.split("|") |> List.delete_at(-1)
  end

  def broadcast_snapshot(camera_exid, image, timestamp) do
    EvercamMediaWeb.Endpoint.broadcast(
      "cameras:#{camera_exid}",
      "snapshot-taken",
      %{image: Base.encode64(image), timestamp: timestamp})
  end

  def broadcast_camera_status(camera_exid, status, username) do
    EvercamMediaWeb.Endpoint.broadcast(
      "users:#{username}",
      "camera-status-changed",
      %{camera_id: camera_exid, status: status})
  end

  def broadcast_camera_share(camera, username) do
    EvercamMediaWeb.Endpoint.broadcast(
      "users:#{username}",
      "camera-share",
      camera)
  end

  def broadcast_camera_response(camera_exid, timestamp, response_time, description, response_type) do
    EvercamMediaWeb.Endpoint.broadcast(
      "livetail:#{camera_exid}",
      "camera-response",
      %{timestamp: timestamp, res_time: response_time, response: response_type, description: description})
  end

  def error_handler(error) do
    Logger.error inspect(error)
    Logger.error Exception.format_stacktrace System.stacktrace
  end

  defp format_token_message(args) do
    [""]
    |> Enum.into(args)
    |> Enum.join("|")
    |> pad_token_message
  end

  defp pad_token_message(message) do
    case rem(String.length(message), 16) do
      0 -> message
      _ -> pad_token_message("#{message} ")
    end
  end

  def ecto_datetime_to_unix(nil), do: nil
  def ecto_datetime_to_unix(ecto_datetime) do
    ecto_datetime
    |> Ecto.DateTime.to_erl
    |> Calendar.DateTime.from_erl!("Etc/UTC")
    |> Calendar.DateTime.Format.unix
  end

  def get_list(values) when values in [nil, ""], do: []
  def get_list(values) do
    values
    |> String.split(",", trim: true)
  end

  def parse_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn
      {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
      msg -> msg
    end)
  end

  def slugify(string) do
    string |> String.normalize(:nfd) |> String.replace(~r/[^A-z0-9-\s]/u, "")
  end

  def create_HMAC(username, intercom_key) do
    :crypto.hmac(:sha256, intercom_key, username)
    |> Base.encode16
    |> String.downcase
  end

  def kill_all_ffmpegs do
    Porcelain.shell("for pid in $(ps -ef | grep ffmpeg | grep 'rtsp://' | grep -v grep |  awk '{print $2}'); do kill -9 $pid; done")
    spawn(fn -> Camera.all |> Enum.map(&(invalidate_response_time_cache &1)) end)
  end

  def invalidate_response_time_cache(nil), do: :noop
  def invalidate_response_time_cache(camera) do
    ConCache.delete(:camera_response_times, camera.exid)
  end
end
