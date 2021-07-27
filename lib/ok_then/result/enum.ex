defmodule OkThen.Result.Enum do
  @moduledoc """
  Functions for processing tagged tuples inside Enums.
  """

  alias OkThen.Result
  alias Result.Private
  require Private

  @doc """
  Collects an Enum of results into a single result. If all results were tagged `:ok`, then a
  result will be returned tagged with `:ok`, whose value is a list of the wrapped values from each
  element in the list. Otherwise, the result whose tag didn't match `tag` is returned.

  Equivalent to `collect_tagged(results, :ok)`. See `collect_tagged/2`.

  ## Examples

      iex> [:ok, :ok]
      ...> |> Result.Enum.collect()
      {:ok, [{}, {}]}

      iex> [:ok, :ok, :ok, :error, {:error, 2}]
      ...> |> Result.Enum.collect()
      {:error, {}}

      iex> [{:ok, 1}, {:ok, 1, 2}, :ok]
      ...> |> Result.Enum.collect()
      {:ok, [1, {1, 2}, {}]}

      iex> [{:ok, 1}, {:ok, 1, 2}, {:something, 1}, :ok]
      ...> |> Result.Enum.collect()
      {:something, 1}

      iex> []
      ...> |> Result.Enum.collect()
      {:ok, []}
  """
  @spec collect([Result.tagged()]) :: {atom(), [any()]}
  def collect(results), do: collect_tagged(results, :ok)

  @doc """
  Collects an Enum of results into a single result. If all results were tagged with the specified
  `tag`, then a result will be returned tagged with `tag`, whose value is a list of the wrapped
  values from each element in the list. Otherwise, the result whose tag didn't match `tag` is
  returned.

  ## Examples

      iex> [:ok, :ok]
      ...> |> Result.Enum.collect_tagged(:ok)
      {:ok, [{}, {}]}

      iex> [:ok, :ok, :ok, :error, {:error, 2}]
      ...> |> Result.Enum.collect_tagged(:ok)
      {:error, {}}

      iex> [{:ok, 1}, {:ok, 1, 2}, :ok]
      ...> |> Result.Enum.collect_tagged(:ok)
      {:ok, [1, {1, 2}, {}]}

      iex> [{:ok, 1}, {:ok, 1, 2}, {:something, 1}, :ok]
      ...> |> Result.Enum.collect_tagged(:ok)
      {:something, 1}

      iex> []
      ...> |> Result.Enum.collect_tagged(:ok)
      {:ok, []}
  """
  @spec collect_tagged([Result.tagged()], atom()) :: {atom(), [any()]}
  def collect_tagged(results, tag) do
    results
    |> Enum.map(&Private.normalize_result_input/1)
    |> Enum.reduce({tag, []}, fn
      {^tag, value}, {^tag, out_list} -> {tag, [value | out_list]}
      other_result, {^tag, _out_list} -> other_result
      _result, acc -> acc
    end)
    |> Result.tagged_map(tag, &Enum.reverse/1)
  end

  @doc """
  Modifies an Enum of results by applying `filter_function` to each group of values separately,
  according to their tag.

  **Note:** The ordering of results is not maintained.

  ## Examples

      iex> [{:ok, 1}, {:ok, 2}, :error, :error]
      ...> |> Result.Enum.map_grouped_by_tag(fn
      ...>   :ok, values -> Enum.map(values, &(&1 + 1))
      ...>   :error, _values -> []
      ...> end)
      [{:ok, 2}, {:ok, 3}]

      iex> [{:ok, 1}]
      ...> |> Result.Enum.map_grouped_by_tag(fn
      ...>   :ok, _values -> nil
      ...> end)
      ** (ArgumentError) Expected map_function clause for tag :ok to return a list, but got: nil

      iex> [{:ok, 1}, {:error, 1}, {:ok, 2}, {:error, 2}, :none]
      ...> |> Result.Enum.map_grouped_by_tag(fn
      ...>   :ok, values -> Enum.map(values, &(&1 + 1))
      ...>   :error, values -> Enum.take(values, 1)
      ...>   :none, _values -> []
      ...> end)
      [{:error, 1}, {:ok, 2}, {:ok, 3}]

      iex> [{:some, 1}, :other, {:some, 2}]
      ...> |> Result.Enum.map_grouped_by_tag(fn
      ...>   :some, values -> Enum.map(values, &(&1 + 1))
      ...>   :other, _values -> []
      ...> end)
      [{:some, 2}, {:some, 3}]

      iex> [:ok, "hello", {:error, "hello"}, {1, 2}]
      ...> |> Result.Enum.map_grouped_by_tag(fn
      ...>   tag, _values when tag in [:ok, :error] -> []
      ...>   :untagged, values -> values
      ...> end)
      [{:untagged, "hello"}, {:untagged, {1, 2}}]

      iex> []
      ...> |> Result.Enum.map_grouped_by_tag(fn
      ...>   :ok, values -> Enum.map(values, &(&1 + 1))
      ...> end)
      []
  """
  @spec map_grouped_by_tag([Result.tagged()], (atom(), [any()] -> [any()])) :: [Result.tagged()]
  def map_grouped_by_tag(results, map_function)
      when is_list(results) and is_function(map_function, 2) do
    results
    |> group_by_tag()
    |> Enum.flat_map(fn {tag, values} ->
      map_function.(tag, values)
      |> case do
        list when is_list(list) ->
          Enum.map(list, &{tag, &1})

        other ->
          raise ArgumentError,
                "Expected map_function clause for tag #{Kernel.inspect(tag)} " <>
                  "to return a list, but got: #{Kernel.inspect(other)}"
      end
    end)
  end

  @doc """
  Collects an Enum of results into a map, with result values grouped by their tag.

  ## Examples

      iex> [:ok, :ok, :ok, :error, :error]
      ...> |> Result.Enum.group_by_tag()
      %{
        error: [{}, {}],
        ok: [{}, {}, {}]
      }

      iex> [{:ok, 1}, {:ok, 2}, {:ok, 3}, {:error, 4}, {:error, 5}]
      ...> |> Result.Enum.group_by_tag()
      %{
        error: [4, 5],
        ok: [1, 2, 3]
      }

      iex> [{:ok, 1}, {:ok, 2, 3}, :none, {:error, 4}, {:another, 5}]
      ...> |> Result.Enum.group_by_tag()
      %{
        another: [5],
        error: [4],
        none: [{}],
        ok: [1, {2, 3}]
      }

      iex> [{:ok, 1}, "hello", {1, 2}]
      ...> |> Result.Enum.group_by_tag()
      %{
        ok: [1],
        untagged: ["hello", {1, 2}]
      }

      iex> []
      ...> |> Result.Enum.group_by_tag()
      %{}
  """
  @spec group_by_tag([Result.tagged()]) :: %{atom() => [any()]}
  def group_by_tag(results) when is_list(results) do
    results
    |> Enum.map(&Private.normalize_result_input/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
