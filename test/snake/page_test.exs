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
    assert state.screensaver == false
    assert length(state.snake) == 3
    assert "Score 0" in texts(state)
    assert "z saver" in texts(state)
  end

  test "an arrow is taken on the next tick and a reverse is not" do
    state = Page.init()
    {hx, hy} = hd(state.snake)
    {:ok, turned} = Page.handle_key({:move, :up}, state)

    assert hd(Page.tick(turned).snake) == {hx, hy - 1}

    {:ok, reversed} = Page.handle_key({:move, :left}, state)
    assert hd(Page.tick(reversed).snake) == {hx + 1, hy}
  end

  test "z plays by itself and an arrow takes over" do
    {:ok, saver} = Page.handle_key({:char, ?z}, Page.init())

    assert saver.screensaver
    assert "Saver 0" in texts(saver)
    assert "z play" in texts(saver)

    {:ok, playing} = Page.handle_key({:move, :up}, saver)
    assert playing.screensaver == false
    assert playing.queued == :up
    assert playing.x0 == saver.x0
    assert playing.cell == saver.cell
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

  test "r does nothing while the snake is alive" do
    assert Page.handle_key({:char, ?r}, Page.init()) == :ignore
  end

  test "the screensaver starts over without losing the board" do
    state = Page.init()
    {:ok, saver} = Page.handle_key({:char, ?z}, state)
    dead = %{saver | alive: false, restart_in: 1, score: 4, move_at: saver.now}
    restarted = Page.tick(dead)

    assert restarted.alive
    assert restarted.screensaver
    assert restarted.score == 0
    assert restarted.x0 == state.x0
    assert restarted.y0 == state.y0
    assert restarted.cell == state.cell
  end

  test "home is left to the router" do
    assert Page.handle_key({:nav, :home}, Page.init()) == :ignore
  end

  test "the head sits on its cell and the panel background is not drawn" do
    state = %{Page.init() | now: 0}
    {col, row} = hd(state.snake)

    assert {_, _, w, h, 0xE8FFF4} =
             Enum.find(rects(state), fn {x, y, _, _, colour} ->
               x == state.x0 + col * state.cell + 1 and y == state.y0 + row * state.cell + 1 and colour == 0xE8FFF4
             end)

    assert w == state.cell - 2
    assert h == state.cell - 2
    refute Enum.any?(rects(state), fn {x, y, w, h, _} -> x == 0 and y == 0 and w >= 320 and h >= 240 end)

    assert {:scaled_cropped_image, 2, 76, 316, 88, :transparent, 0, 0, 4, 4, [], {:rgba8888, 79, 22, sprite}} =
             watermark(state)

    assert byte_size(sprite) == 79 * 22 * 4
  end

  test "the food blinks white and red" do
    state = Page.init()
    assert food_color(%{state | now: 0}) == 0xFFFFFF
    assert food_color(%{state | now: 200}) == 0xFF0000
  end

  test "a frame is due every tick so the word can move between steps" do
    assert Page.refresh(Page.init()) == 100
  end

  test "death says so" do
    state = %{Page.init() | alive: false, score: 3}
    assert "Dead 3" in texts(state)
    assert "r restart" in texts(state)
  end

  defp food_color(state) do
    {col, row} = state.food

    {_, _, _, _, colour} =
      Enum.find(rects(state), fn {x, y, _, _, _} ->
        x == state.x0 + col * state.cell + 1 and y == state.y0 + row * state.cell + 1
      end)

    colour
  end

  defp watermark(state) do
    Enum.find(Page.render(state), fn
      {:scaled_cropped_image, _, _, _, _, _, _, _, _, _, _, _} -> true
      _ -> false
    end)
  end
end
