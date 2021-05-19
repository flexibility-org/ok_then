defmodule OkThen.Result.Pipe do
  @moduledoc """
  Convenience operators for handling of tagged results in pipelines.
  """

  alias OkThen.Result

  # We don't want `Elixir.` at the start of the module name.
  @result_module Result
                 |> Module.split()
                 |> Enum.join(".")

  @doc """
  Equivalent to `#{@result_module}.map(result, func_or_default)`. See `#{@result_module}.map/2`.

  ## Examples

      iex> add_one = &(&1 + 1)
      iex> {:ok, 1}
      ...> ~> add_one.()
      ...> ~> add_one.()
      {:ok, 3}

      iex> add_one = &(&1 + 1)
      iex> {:error, 1}
      ...> ~> add_one.()
      ...> ~> add_one.()
      {:error, 1}

      iex> {:ok, 1}
      ...> ~> "hello"
      {:ok, "hello"}

      iex> {:error, 1}
      ...> ~> "hello"
      {:error, 1}

      iex> "bare value"
      ...> ~> "hello"
      "bare value"

      iex> add_one = &(&1 + 1)
      iex> "bare value"
      ...> ~> add_one.()
      "bare value"
  """
  defmacro result ~> {call, line, args} do
    quoted_value = quote do: value
    args = [quoted_value | args]

    quote do
      Result.map(unquote(result), fn value -> unquote({call, line, args}) end)
    end
  end

  defmacro result ~> func_or_default do
    quote do
      Result.map(unquote(result), fn value -> unquote(func_or_default) end)
    end
  end

  @doc """
  Equivalent to `#{@result_module}.then(result, func_or_default)`. See `#{@result_module}.then/2`.

  ## Examples

      iex> add_one = &({:ok, &1 + 1})
      iex> {:ok, 1}
      ...> ~>> add_one.()
      ...> ~>> add_one.()
      {:ok, 3}

      iex> add_one = &({:ok, &1 + 1})
      iex> {:error, 1}
      ...> ~>> add_one.()
      ...> ~>> add_one.()
      {:error, 1}

      iex> {:ok, 1}
      ...> ~>> {:ok, "hello"}
      {:ok, "hello"}

      iex> {:error, 1}
      ...> ~>> {:ok, "hello"}
      {:error, 1}

      iex> "bare value"
      ...> ~>> {:ok, "hello"}
      "bare value"

      iex> add_one = &(&1 + 1)
      iex> "bare value"
      ...> ~>> add_one.()
      "bare value"
  """
  defmacro result ~>> {call, line, args} do
    quoted_value = quote do: value
    args = [quoted_value | args]

    quote do
      Result.then(unquote(result), fn value -> unquote({call, line, args}) end)
    end
  end

  defmacro result ~>> func_or_default do
    quote do
      Result.then(unquote(result), fn value -> unquote(func_or_default) end)
    end
  end
end
