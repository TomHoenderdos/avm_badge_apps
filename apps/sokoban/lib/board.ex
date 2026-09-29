defmodule Badge.App.Sokoban.Board do
  @moduledoc """
  One Sokoban position as a plain map, parsed from XSB text.

  `#` wall, `.` goal, `$` box, `*` box on a goal, `@` player, `+` player on a
  goal; anything else is floor. Positions are `{x, y}`, 0-based from the
  top-left. `move/2` returns the new board and what happened.
  """

  @doc "Parses one level of XSB text."
  @spec parse(binary) :: map
  def parse(xsb),
    do: parse(xsb, 0, 0, %{w: 0, h: 0, walls: [], goals: [], boxes: [], player: nil})

  defp parse(<<>>, x, y, board),
    do: %{board | w: max(board.w, x), h: if(x > 0, do: y + 1, else: y)}

  defp parse(<<?\n, rest::binary>>, x, y, board),
    do: parse(rest, 0, y + 1, %{board | w: max(board.w, x)})

  defp parse(<<c, rest::binary>>, x, y, board), do: parse(rest, x + 1, y, cell(c, {x, y}, board))

  defp cell(?#, at, board), do: %{board | walls: [at | board.walls]}
  defp cell(?., at, board), do: %{board | goals: [at | board.goals]}
  defp cell(?$, at, board), do: %{board | boxes: [at | board.boxes]}
  defp cell(?*, at, board), do: %{board | boxes: [at | board.boxes], goals: [at | board.goals]}
  defp cell(?@, at, board), do: %{board | player: at}
  defp cell(?+, at, board), do: %{board | player: at, goals: [at | board.goals]}
  defp cell(_floor, _at, board), do: board

  @doc "Steps the player one square, pushing a box when the square behind it is free."
  @spec move(map, atom) :: {:moved | :pushed | :blocked, map}
  def move(board, dir) do
    next = step(board.player, dir)

    cond do
      :lists.member(next, board.walls) -> {:blocked, board}
      :lists.member(next, board.boxes) -> push(board, next, step(next, dir))
      true -> {:moved, %{board | player: next}}
    end
  end

  defp push(board, box, beyond) do
    case :lists.member(beyond, board.walls) or :lists.member(beyond, board.boxes) do
      true ->
        {:blocked, board}

      false ->
        {:pushed, %{board | player: box, boxes: [beyond | :lists.delete(box, board.boxes)]}}
    end
  end

  defp step({x, y}, :up), do: {x, y - 1}
  defp step({x, y}, :down), do: {x, y + 1}
  defp step({x, y}, :left), do: {x - 1, y}
  defp step({x, y}, :right), do: {x + 1, y}

  @doc "Whether every box sits on a goal."
  @spec solved?(map) :: boolean
  def solved?(board), do: :lists.all(fn box -> :lists.member(box, board.goals) end, board.boxes)

  @doc "Walls as horizontal runs `{x, y, length}`, top to bottom, left to right."
  @spec runs(map) :: [{integer, integer, pos_integer}]
  def runs(board), do: join(:lists.sort(for({x, y} <- board.walls, do: {y, x})), [])

  defp join([], acc), do: :lists.reverse(acc)

  defp join([{y, x} | rest], [{rx, y, n} | acc]) when rx + n == x,
    do: join(rest, [{rx, y, n + 1} | acc])

  defp join([{y, x} | rest], acc), do: join(rest, [{x, y, 1} | acc])
end
