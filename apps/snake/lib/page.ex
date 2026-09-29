defmodule Badge.App.Snake.Page do
  @moduledoc """
  Steer into the food. Arrows turn, `r` starts again. Esc goes home.

  The board is as many cells as fit between the title bar and the status
  line. `tick/1` advances one cell; `refresh/1` is the gap between moves.
  """

  use Badge.Page

  alias Badge.App.Snake.Game
  alias Badge.FontType
  alias Badge.Readout
  alias Badge.Theme

  @cell 10
  @tick 140
  @bar_y 216
  @margin 8

  @impl true
  def title, do: "Snake"

  @impl true
  def icon, do: :circle

  @impl true
  def init do
    {cols, rows, x0, y0} = layout()
    Map.merge(Game.new(cols, rows), %{x0: x0, y0: y0, cell: @cell})
  end

  @impl true
  def handle_key({:move, dir}, state) when dir == :up or dir == :down or dir == :left or dir == :right do
    {:ok, Game.turn(state, dir)}
  end

  def handle_key({:char, c}, state) when c == ?r or c == ?R, do: {:ok, restart(state)}
  def handle_key(_event, _state), do: :ignore

  @impl true
  def tick(state), do: Game.tick(state)

  @impl true
  def refresh(_state), do: @tick

  @impl true
  def render(state), do: snake(state) ++ [food(state) | bar(state)]

  defp restart(state) do
    game = Game.restart(state)
    Map.merge(game, %{x0: state.x0, y0: state.y0, cell: state.cell})
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

  defp snake(%{snake: [head | body]} = state) do
    [cell(state, head, Theme.accent()) | segments(body, state, [])]
  end

  defp segments([], _state, acc), do: :lists.reverse(acc)

  defp segments([part | rest], state, acc) do
    segments(rest, state, [cell(state, part, Theme.ok()) | acc])
  end

  defp food(state), do: cell(state, state.food, Theme.warn())

  defp cell(state, {col, row}, colour) do
    inset = 1

    {:rect, state.x0 + col * state.cell + inset, state.y0 + row * state.cell + inset, state.cell - 2 * inset, state.cell - 2 * inset,
     colour}
  end

  defp bar(state) do
    font = FontType.heading()
    where = status(state) <> " " <> int(state.score)

    Theme.rule(0, @bar_y, Theme.width()) ++
      [
        {:text, @margin, @bar_y + 2, font, Theme.dim(), Theme.bg(), "r restart"},
        {:text, Readout.right_x(where, font), @bar_y + 2, font, Theme.fg(), Theme.bg(), where}
      ]
  end

  defp status(%{alive: false}), do: "Dead"
  defp status(_state), do: "Score"

  defp int(n), do: :erlang.integer_to_binary(n)
end
