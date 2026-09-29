defmodule Badge.App.Snake.Game do
  @moduledoc "Snake rules. The head is the first cell. `seed` only picks food."

  import Bitwise

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
      seed: seed
    }

    {food, seed} = place_food(state)
    %{state | food: food, seed: seed}
  end

  def turn(%{alive: false} = state, _dir), do: state
  def turn(state, :up), do: queue(state, :up)
  def turn(state, :down), do: queue(state, :down)
  def turn(state, :left), do: queue(state, :left)
  def turn(state, :right), do: queue(state, :right)

  def tick(%{alive: false} = state), do: state

  def tick(state) do
    dir = state.queued
    [{hx, hy} | _] = state.snake
    head = step({hx, hy}, dir)
    growing = head == state.food
    body = if growing, do: state.snake, else: drop_last(state.snake)

    cond do
      not inside?(head, state) or member?(head, body) ->
        %{state | dir: dir, alive: false}

      growing ->
        grown = %{state | snake: [head | state.snake], dir: dir, score: state.score + 1}

        case grown.cols * grown.rows - length(grown.snake) do
          0 ->
            %{grown | alive: false}

          _free ->
            {food, seed} = place_food(grown)
            %{grown | food: food, seed: seed}
        end

      true ->
        %{state | snake: [head | body], dir: dir}
    end
  end

  def restart(state), do: new(state.cols, state.rows, xorshift(state.seed))

  defp queue(state, dir) do
    if opposite?(state.dir, dir), do: state, else: %{state | queued: dir}
  end

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
