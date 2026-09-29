defmodule Badge.App.Race.TiltTest do
  use ExUnit.Case, async: true

  alias Badge.App.Race.Tilt

  test "a failed sensor read is survived, and the poller ends with its reader" do
    reader = spawn(fn -> receive do: (:stop -> :ok) end)
    tilt = Tilt.start(reader)
    ref = Process.monitor(tilt)

    Process.sleep(250)
    assert Process.alive?(tilt)

    send(reader, :stop)
    assert_receive {:DOWN, ^ref, :process, ^tilt, _reason}, 500
  end

  test "stop kills it" do
    tilt = Tilt.start(self())
    ref = Process.monitor(tilt)
    Tilt.stop(tilt)
    assert_receive {:DOWN, ^ref, :process, ^tilt, :killed}, 500
  end
end
