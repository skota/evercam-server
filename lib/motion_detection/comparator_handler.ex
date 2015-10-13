defmodule EvercamMedia.MotionDetection.ComparatorHandler do
  use GenEvent
  require Logger
  alias EvercamMedia.Repo
  import Ecto.Query

  @moduledoc """
  TODO
  """

  def handle_event({:got_snapshot, data}, state) do
    {camera_exid, timestamp, image} = data
    image_byte_size = byte_size image
    Logger.info "Inside EvercamMedia.MotionDetection.ComparatorHandler -> handle_event"
    Logger.info "camera_exid=#{camera_exid}"

    camera_exid_last = "#{camera_exid}_last"
    camera_exid_previous = "#{camera_exid}_previous"

    # last_timestamp = result[:timestamp]
    # last_notes = result[:notes]

    last = ConCache.get(:cache, camera_exid_last)
    previous = ConCache.get(:cache, camera_exid_previous)

    last_image = last[:image]
    previous_image = previous[:image]

    Logger.info "last = #{last[:timestamp]}, previous = #{previous[:timestamp]}"

    if last_image && previous_image do
      EvercamMedia.MotionDetection.Lib.init
      motion_level = EvercamMedia.MotionDetection.Lib.compare(last_image,previous_image)
      Logger.info "motion_level = #{motion_level}"

      update_snapshot_status("#{camera_exid}", previous[:timestamp], motion_level)
    end

    {:ok, state}
  end

  def update_snapshot_status(camera_exid, seconds, motion_level) do
    camera = Repo.one! Camera.by_exid(camera_exid)
    tt = Timex.Date.from(seconds, :secs)
    # Timex.DateTime{calendar: :gregorian, day: 13, hour: 22, minute: 41, month: 10, ms: 0, second: 25, timezone: %Timex.TimezoneInfo{abbreviation: "UTC", from: :min, full_name: "UTC", offset_std: 0, offset_utc: 0, until: :max}, year: 2015}}
    year = tt.year
    month = tt.month
    day = tt.day

    hour = tt.hour
    min = tt.minute
    sec = tt.second
    usec = tt.ms

    data = Ecto.DateTime.cast({{year, month, day}, {hour, min, sec, usec}})
    {:ok,timestamp} = data

    snapshot = Repo.one! Snapshot.for_camera(camera.id,timestamp)
    Logger.info "update_snapshot_status snapshot=#{snapshot[:created_at]}"

    # camera = %{camera | MotionLevel: S3.file_url(file_path)}
    #
    # Repo.insert %Snapshot{camera_id: camera.id, data: "S3", notes: "Evercam Proxy", created_at: timestamp}
    #
    # Repo.update camera
  end

  def handle_event(_, state) do
    {:ok, state}
  end

end
