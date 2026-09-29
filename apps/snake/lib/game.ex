defmodule Badge.App.Snake.Game do
  @moduledoc """
  Snake rules. The head is the first cell. `seed` picks the food.

  In screensaver mode the snake plays by itself: it heads for the food
  without running into a wall, its body or a pocket it cannot leave, and
  after a crash it starts over on its own.
  """

  import Bitwise

  # Ticks the crash stays on screen before the screensaver starts over.
  @pause 8

  def new(cols, rows, seed \\ 0xC0FFEE)
      when is_integer(cols) and is_integer(rows) and cols >= 8 and rows >= 8 do
    y = div(rows, 2)

    state = %{
      cols: cols,
      rows: rows,
      snake: [{2, y}, {1, y}, {0, y}],
      dir: :right,
      queued: :right,
      food: nil,
      score: 0,
      alive: true,
      seed: seed,
      screensaver: false,
      restart_in: 0
    }

    {food, seed} = place_food(state)
    %{state | food: food, seed: seed}
  end

  def turn(%{alive: false} = state, _dir), do: state
  def turn(state, :up), do: queue(state, :up)
  def turn(state, :down), do: queue(state, :down)
  def turn(state, :left), do: queue(state, :left)
  def turn(state, :right), do: queue(state, :right)

  def screensaver(state, enabled \\ true)

  def screensaver(%{alive: false} = state, true), do: restart(%{state | screensaver: true})
  def screensaver(state, true), do: %{state | screensaver: true}
  def screensaver(state, false), do: %{state | screensaver: false}

  def toggle_screensaver(%{screensaver: on} = state), do: screensaver(state, not on)

  def tick(%{alive: false, screensaver: true, restart_in: n} = state) when n <= 1,
    do: restart(state)

  def tick(%{alive: false, screensaver: true} = state),
    do: %{state | restart_in: state.restart_in - 1}

  def tick(%{alive: false} = state), do: state

  def tick(state) do
    state = steer(state)
    dir = state.queued
    [{hx, hy} | _] = state.snake
    head = step({hx, hy}, dir)
    growing = head == state.food
    body = if growing, do: state.snake, else: drop_last(state.snake)

    cond do
      not inside?(head, state) or member?(head, body) ->
        %{state | dir: dir, alive: false, restart_in: @pause}

      growing ->
        grown = %{state | snake: [head | state.snake], dir: dir, score: state.score + 1}

        case grown.cols * grown.rows - length(grown.snake) do
          0 ->
            %{grown | alive: false, restart_in: @pause}

          _free ->
            {food, seed} = place_food(grown)
            %{grown | food: food, seed: seed}
        end

      true ->
        %{state | snake: [head | body], dir: dir}
    end
  end

  def restart(%{screensaver: screensaver} = state) do
    state.cols
    |> new(state.rows, xorshift(state.seed))
    |> screensaver(screensaver)
  end

  defp queue(state, dir) do
    if opposite?(state.dir, dir), do: state, else: %{state | queued: dir}
  end

  defp steer(%{screensaver: true} = state), do: %{state | queued: pilot(state)}
  defp steer(state), do: state

  # Straight on, or a turn, whichever is safe and brings the head nearest
  # the food. A move into a pocket smaller than the snake counts as unsafe
  # unless every move does. With nothing safe the snake keeps going.
  defp pilot(state) do
    [head | _] = state.snake
    options = [state.dir, veer(state.dir, :left), veer(state.dir, :right)]
    choose(options, head, state, 0, nil)
  end

  defp choose([], _head, state, _order, nil), do: state.dir
  defp choose([], _head, _state, _order, {_key, dir}), do: dir

  defp choose([dir | rest], head, state, order, best) do
    cell = step(head, dir)
    body = after_move(state, cell)

    best =
      if inside?(cell, state) and not Map.has_key?(body, cell) do
        key = {squeeze(cell, body, state), distance(cell, state.food), order}
        prefer(best, {key, dir})
      else
        best
      end

    choose(rest, head, state, order + 1, best)
  end

  # Earlier options win a tie, so straight ahead beats a turn.
  defp prefer(nil, candidate), do: candidate
  defp prefer({key, _}, {other, _} = candidate) when other < key, do: candidate
  defp prefer(best, _candidate), do: best

  # Cells the body will occupy once the head has moved to `cell`.
  defp after_move(state, cell) do
    body = if cell == state.food, do: state.snake, else: drop_last(state.snake)
    Enum.reduce(body, %{}, fn occupied, map -> Map.put(map, occupied, true) end)
  end

  # How many cells short of the snake's length the room around `cell` is.
  defp squeeze(cell, body, state) do
    need = length(state.snake)
    max(need - reachable([cell], %{cell => true}, body, state, need, 0), 0)
  end

  defp reachable([], _seen, _body, _state, _cap, count), do: count
  defp reachable(_cells, _seen, _body, _state, cap, count) when count >= cap, do: count

  defp reachable([cell | rest], seen, body, state, cap, count) do
    {frontier, seen} =
      Enum.reduce([:up, :down, :left, :right], {rest, seen}, fn dir, {frontier, seen} ->
        next = step(cell, dir)

        if inside?(next, state) and not Map.has_key?(body, next) and
             not Map.has_key?(seen, next) do
          {[next | frontier], Map.put(seen, next, true)}
        else
          {frontier, seen}
        end
      end)

    reachable(frontier, seen, body, state, cap, count + 1)
  end

  defp distance(_cell, nil), do: 0
  defp distance({x, y}, {fx, fy}), do: abs(x - fx) + abs(y - fy)

  defp veer(:up, :left), do: :left
  defp veer(:up, :right), do: :right
  defp veer(:down, :left), do: :right
  defp veer(:down, :right), do: :left
  defp veer(:left, :left), do: :down
  defp veer(:left, :right), do: :up
  defp veer(:right, :left), do: :up
  defp veer(:right, :right), do: :down

  defp place_food(state) do
    free = state.cols * state.rows - length(state.snake)
    {n, seed} = next_int(state.seed, free)
    {nth_free(n, 0, 0, state), seed}
  end

  defp nth_free(n, x, y, state) when x == state.cols, do: nth_free(n, 0, y + 1, state)

  defp nth_free(n, x, y, state) do
    cell = {x, y}

    if member?(cell, state.snake) do
      nth_free(n, x + 1, y, state)
    else
      if n == 0, do: cell, else: nth_free(n - 1, x + 1, y, state)
    end
  end

  defp next_int(seed, bound) do
    seed = xorshift(seed)
    {rem(seed, bound), seed}
  end

  defp xorshift(seed) do
    x = bxor(seed, bsl(seed, 13))
    x = bxor(x, bsr(x, 17))
    bxor(x, bsl(x, 5)) &&& 0x7FFFFFFF
  end

  defp step({x, y}, :up), do: {x, y - 1}
  defp step({x, y}, :down), do: {x, y + 1}
  defp step({x, y}, :left), do: {x - 1, y}
  defp step({x, y}, :right), do: {x + 1, y}

  defp inside?({x, y}, state), do: x >= 0 and y >= 0 and x < state.cols and y < state.rows

  defp opposite?(:up, :down), do: true
  defp opposite?(:down, :up), do: true
  defp opposite?(:left, :right), do: true
  defp opposite?(:right, :left), do: true
  defp opposite?(_, _), do: false

  defp member?(_cell, []), do: false
  defp member?(cell, [cell | _]), do: true
  defp member?(cell, [_ | rest]), do: member?(cell, rest)

  defp drop_last([_]), do: []
  defp drop_last([head | rest]), do: [head | drop_last(rest)]
end
