defmodule Badge.App.Snake.Page do
  @moduledoc """
  Steer into the food. Arrows turn, `z` lets the snake play, `r` starts
  again. Esc goes home.

  The board is as many cells as fit between the title bar and the status
  line. The snake moves every 140 ms. Between moves the clock still
  advances, so the food and the word can blink.
  """

  use Badge.Page

  alias Badge.App.Snake.Game
  alias Badge.App.Snake.Render
  alias Badge.FontType
  alias Badge.Readout
  alias Badge.Theme

  @cell 10
  @move 140
  @bar_y 216
  @margin 8

  @impl true
  def title, do: "Snake"

  @impl true
  def icon, do: :circle

  @impl true
  def init do
    {cols, rows, x0, y0} = layout()
    now = now()
    Map.merge(Game.new(cols, rows), %{x0: x0, y0: y0, cell: @cell, now: now, move_at: now})
  end

  @impl true
  def handle_key({:move, dir}, state) when dir == :up or dir == :down or dir == :left or dir == :right do
    state = if state.screensaver, do: Game.screensaver(state, false), else: state
    {:ok, Game.turn(state, dir)}
  end

  def handle_key({:char, c}, state) when c == ?z or c == ?Z, do: {:ok, place(Game.toggle_screensaver(state), state)}
  def handle_key({:char, c}, %{alive: false} = state) when c == ?r or c == ?R, do: {:ok, place(Game.restart(state), state)}
  def handle_key(_event, _state), do: :ignore

  @impl true
  def tick(state) do
    now = now()

    if now >= state.move_at do
      state |> Map.put(:now, now) |> Game.tick() |> place(state, now, now + @move)
    else
      %{state | now: now}
    end
  end

  @impl true
  def refresh(_state), do: 100

  @impl true
  def render(state), do: Render.scene(state, state, state.now) ++ bar(state)

  defp place(game, state), do: place(game, state, state.now, state.move_at)

  defp place(game, state, now, move_at) do
    Map.merge(game, %{x0: state.x0, y0: state.y0, cell: state.cell, now: now, move_at: move_at})
  end

  defp layout do
    top = Theme.content_top()
    area_h = @bar_y - top - 2
    cols = div(Theme.width(), @cell)
    rows = div(area_h, @cell)
    x0 = div(Theme.width() - cols * @cell, 2)
    y0 = top + div(area_h - rows * @cell, 2)
    {cols, rows, x0, y0}
  end

  defp bar(state) do
    font = FontType.heading()
    where = status(state) <> " " <> int(state.score)

    Theme.rule(0, @bar_y, Theme.width()) ++
      [
        {:text, @margin, @bar_y + 2, font, Theme.dim(), Theme.bg(), hint(state)},
        {:text, Readout.right_x(where, font), @bar_y + 2, font, Theme.fg(), Theme.bg(), where}
      ]
  end

  defp hint(%{alive: false}), do: "r restart"
  defp hint(%{screensaver: true}), do: "z play"
  defp hint(_state), do: "z saver"

  defp status(%{alive: false}), do: "Dead"
  defp status(%{screensaver: true}), do: "Saver"
  defp status(_state), do: "Score"

  defp int(n), do: :erlang.integer_to_binary(n)
  defp now, do: :erlang.monotonic_time(:millisecond)
end
