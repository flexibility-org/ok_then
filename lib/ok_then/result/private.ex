defmodule OkThen.Result.Private do
  @moduledoc false

  alias OkThen.Result

  defguard is_tag(value) when is_atom(value) and not is_nil(value)

  defguard is_tagged_with_atom(value, tag)
           when value == tag or (is_tuple(value) and elem(value, 0) == tag)

  @spec normalize_result_input(any(), atom()) :: Result.tagged()
  def normalize_result_input(tag, default_tag \\ :untagged)

  def normalize_result_input(tag, _default_tag) when is_tag(tag), do: {tag, {}}
  def normalize_result_input({tag, _} = term, _default_tag) when is_tag(tag), do: term

  def normalize_result_input(value, _default_tag)
      when is_tuple(value) and is_tag(elem(value, 0)) do
    {elem(value, 0), Tuple.delete_at(value, 0)}
  end

  def normalize_result_input(value, default_tag) when is_tag(default_tag) do
    Result.from_as(value, default_tag)
    |> normalize_result_input()
  end

  @spec normalize_result_output(t) :: t when t: Result.tagged()
  def normalize_result_output({tag, {}}) when is_tag(tag), do: tag
  def normalize_result_output({tag, _} = result) when is_tag(tag), do: result

  @spec normalize_value(any()) :: any()
  def normalize_value({value}), do: value
  def normalize_value(value), do: value

  @spec map_normalized_result(
          Result.tagged(),
          (atom(), any() -> any()) | (any() -> any()) | any()
        ) ::
          Result.result_input()
  def map_normalized_result({tag, value}, func_or_value) when is_function(func_or_value) do
    Function.info(func_or_value, :arity)
    |> case do
      {:arity, 0} -> func_or_value.()
      {:arity, 1} -> func_or_value.(value)
      {:arity, 2} -> func_or_value.(tag, value)
      _ -> raise(ArgumentError, "Value-mapping function must have arity between 0 and 2.")
    end
  end

  def map_normalized_result(_normalized_result, func_or_value), do: func_or_value

  @spec map_value(any(), (any() -> any()) | any()) :: any()
  def map_value(value, func_or_value) when is_function(func_or_value) do
    Function.info(func_or_value, :arity)
    |> case do
      {:arity, 0} -> func_or_value.()
      {:arity, 1} -> func_or_value.(value)
      _ -> raise(ArgumentError, "Value-mapping function must have arity between 0 and 1.")
    end
  end

  def map_value(_value, func_or_value), do: func_or_value
end
