defmodule Badge.App.Race.Tilt do
  @moduledoc """
  Reads the badge's sideways lean ten times a second and sends it on as
  `{:tilt, milli_g}`: gravity along the panel's horizontal axis, sensor X,
  which follows a turn whether the badge is held flat or upright.

      pid = Tilt.start(self())
      Tilt.stop(pid)

  Not linked: if it dies, only the tilt is lost. It ends by itself once the
  process it reports to is gone.
  """

  alias Badge.Sensors

  @every_ms 100

  @doc "Starts reporting to `to`."
  def start(to), do: spawn(fn -> loop(to) end)

  @doc "Stops it."
  def stop(pid), do: Process.exit(pid, :kill)

  defp loop(to) do
    case Process.alive?(to) do
      true ->
        report(to)
        Process.sleep(@every_ms)
        loop(to)

      false ->
        :ok
    end
  end

  defp report(to) do
    try do
      {x, _y, _z} = Sensors.acceleration()
      send(to, {:tilt, x})
    catch
      _kind, _reason -> :ok
    end
  end
end
