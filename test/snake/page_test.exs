defmodule Badge.App.Snake.PageTest do
  use ExUnit.Case, async: true

  alias Badge.App.Snake.Page

  defp texts(state), do: for({:text, _x, _y, _font, _fg, _bg, text} <- Page.render(state), do: text)

  defp rects(state), do: for({:rect, x, y, w, h, colour} <- Page.render(state), do: {x, y, w, h, colour})

  test "opens alive with a score of zero" do
    state = Page.init()

    assert state.alive
    assert state.score == 0
    assert state.dir == :right
    assert length(state.snake) == 3
    assert "Score 0" in texts(state)
  end

  test "an arrow is taken on the next tick and a reverse is not" do
    state = Page.init()
    {hx, hy} = hd(state.snake)
    {:ok, turned} = Page.handle_key({:move, :up}, state)

    assert hd(Page.tick(turned).snake) == {hx, hy - 1}

    {:ok, reversed} = Page.handle_key({:move, :left}, state)
    assert hd(Page.tick(reversed).snake) == {hx + 1, hy}
  end

  test "r starts again and keeps the board geometry" do
    state = Page.init()
    dead = %{state | alive: false, score: 4}
    {:ok, restarted} = Page.handle_key({:char, ?r}, dead)

    assert restarted.alive
    assert restarted.score == 0
    assert restarted.x0 == state.x0
    assert restarted.y0 == state.y0
    assert restarted.cell == state.cell
  end

  test "home is left to the router" do
    assert Page.handle_key({:nav, :home}, Page.init()) == :ignore
  end

  test "the head is the first cell and the panel background is not drawn" do
    state = Page.init()
    {col, row} = hd(state.snake)
    [{x, y, w, h, _colour} | _] = rects(state)

    assert x == state.x0 + col * state.cell + 1
    assert y == state.y0 + row * state.cell + 1
    assert w == state.cell - 2
    assert h == state.cell - 2
    refute Enum.any?(rects(state), fn {x, y, w, h, _} -> x == 0 and y == 0 and w >= 320 and h >= 240 end)
  end

  test "a move is due every 140 ms" do
    assert Page.refresh(Page.init()) == 140
  end

  test "death says so" do
    state = %{Page.init() | alive: false, score: 3}
    assert "Dead 3" in texts(state)
  end
end
