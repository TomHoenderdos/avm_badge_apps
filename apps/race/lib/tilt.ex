defmodule Badge.App.Race.Tilt do
  @moduledoc """
  Reads the badge's roll ten times a second and sends it on as `{:tilt, roll}`.

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
      {roll, _pitch} = Sensors.orientation()
      send(to, {:tilt, roll})
    catch
      _kind, _reason -> :ok
    end
  end
end
