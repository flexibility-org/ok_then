defmodule OkThen.Result do
  @moduledoc """
  Functions to aid processing of tagged tuples in pipelines.

  ## Examples

      iex> 1
      ...> |> Result.from()                # {:ok, 1}
      ...> |> Result.map(& &1 * 2)         # {:ok, 2}
      ...> |> Result.then(& {:ok, &1 + 1}) # {:ok, 3}
      ...> |> Result.unwrap_or_else(0)
      3

      iex> "Oh no!"
      ...> |> Result.from_error()          # {:error, "Oh no!"}
      ...> |> Result.map(& &1 * 2)         # {:error, "Oh no!"}
      ...> |> Result.then(& {:ok, &1 + 1}) # {:error, "Oh no!"}
      ...> |> Result.unwrap_or_else(0)
      0

      iex> {:ok, 1}
      ...> |> Result.map(fn
      ...>      1 -> nil
      ...>      x -> x * 2
      ...>    end)                         # :none
      ...> |> Result.default(3)            # {:ok, 3}
      ...> |> Result.unwrap_or_else(0)
      3

      iex> {:ok, 2}
      ...> |> Result.map(fn
      ...>      1 -> nil
      ...>      x -> x * 2
      ...>    end)                         # {:ok, 4}
      ...> |> Result.default(3)            # {:ok, 4}
      ...> |> Result.unwrap_or_else(0)
      4

      iex> {:error, "Oh no!"}
      ...> |> Result.map(fn
      ...>      1 -> nil
      ...>      x -> x * 2
      ...>    end)                         # {:error, "Oh no!"}
      ...> |> Result.default(3)            # {:error, "Oh no!"}
      ...> |> Result.unwrap_or_else(0)
      0

      iex> {:error, "Oh no!"}
      ...> |> Result.error_then(fn "Oh no!" -> :error end) # :error
      ...> |> Result.or_else(fn -> {:ok, 0} end)           # {:ok, 0}
      ...> |> Result.unwrap!()
      0

      iex> {:ok, 1}
      ...> |> Result.error_then(fn "Oh no!" -> :error end) # {:ok, 1}
      ...> |> Result.or_else(fn -> {:ok, 0} end)           # {:ok, 1}
      ...> |> Result.unwrap!()
      1
  """

  alias __MODULE__, as: Self
  alias Self.Private
  require Private

  @type result_input :: atom() | tuple()
  @type tagged :: atom() | {atom(), any()}

  @type ok(t) :: {:ok, t}
  @type error(t) :: {:error, t}
  @type ok_or(e) :: :ok | error(e)
  @type ok_or(t, e) :: ok(t) | error(e)

  @type maybe_is(t) :: t | :none
  @type maybe_is(t, v) :: {t, v} | :none

  @type maybe :: maybe_is(:ok)
  @type maybe(t) :: maybe_is(:ok, t)
  @type maybe(t, e) :: ok(t) | error(e) | :none
  @type maybe_error :: maybe_is(:error)
  @type maybe_error(e) :: maybe_is(:error, e)

  @typep func_or_value(out) :: (any() -> out) | out
  @typep func_or_value(tag, out) :: (tag, any() -> out) | func_or_value(out)

  @doc section: :guards
  @doc """
  Returns true if `result` is a tagged tuple.

  ## Examples

      iex> Result.is_tagged_tuple(:ok)
      true

      iex> Result.is_tagged_tuple({:ok, "hello"})
      true

      iex> Result.is_tagged_tuple({:error, "hello"})
      true

      iex> Result.is_tagged_tuple({:ok, 1, 2})
      true

      iex> Result.is_tagged_tuple({:ok, {1, 2}})
      true

      iex> Result.is_tagged_tuple({:strange, "hello"})
      true

      iex> Result.is_tagged_tuple({"ok", "hello"})
      false

      iex> func = fn -> "hello" end
      ...> func.() |> Result.is_tagged_tuple()
      false

      iex> func = fn -> nil end
      ...> func.() |> Result.is_tagged_tuple()
      false

      iex> Result.is_tagged_tuple({nil, "hello"})
      false
  """
  defguard is_tagged_tuple(value)
           when Private.is_tag(value) or
                  (is_tuple(value) and Private.is_tag(elem(value, 0)))

  @doc section: :guards
  @doc """
  Returns true if `result` is tagged with the specified `tag` atom.

  ## Examples

      iex> Result.is_tagged(:ok, :ok)
      true

      iex> Result.is_tagged({:ok, "hello"}, :ok)
      true

      iex> Result.is_tagged({:error, "hello"}, :ok)
      false

      iex> Result.is_tagged({:ok, 1, 2}, :ok)
      true

      iex> Result.is_tagged({:ok, {1, 2}}, :ok)
      true

      iex> Result.is_tagged({:strange, "hello"}, :strange)
      true

      iex> hello = fn -> "hello" end
      ...> hello.() |> Result.is_tagged(:ok)
      false
  """
  defguard is_tagged(value, tag)
           when Private.is_tag(tag) and Private.is_tagged_with_atom(value, tag)

  @doc section: :guards
  @doc """
  Returns true if `result` is tagged `:ok`.

  Equivalent to `is_tagged(value, :ok)`. See `is_tagged/2`.

  ## Examples

      iex> Result.is_ok(:ok)
      true

      iex> Result.is_ok({:ok, "hello"})
      true

      iex> Result.is_ok({:error, "hello"})
      false
  """
  defguard is_ok(value) when Private.is_tagged_with_atom(value, :ok)

  @doc section: :guards
  @doc """
  Returns true if `result` is tagged `:error`.

  Equivalent to `is_tagged(value, :error)`. See `is_tagged/2`.

  ## Examples

      iex> Result.is_error(:error)
      true

      iex> Result.is_error({:error, "hello"})
      true

      iex> Result.is_error({:ok, "hello"})
      false
  """
  defguard is_error(value) when Private.is_tagged_with_atom(value, :error)

  @doc section: :guards
  @doc """
  Returns true if `result` is tagged `:none`.

  Equivalent to `is_tagged(value, :none)`. See `is_tagged/2`.

  ## Examples

      iex> Result.is_none(:none)
      true

      iex> Result.is_none({:ok, "hello"})
      false

      iex> Result.is_none({:error, "hello"})
      false
  """
  defguard is_none(value) when Private.is_tagged_with_atom(value, :none)

  @doc section: :ok_functions
  @doc """
  If `result` is tagged with `:ok`, passes the wrapped value into the provided function (if
  provided) and returns `:none`.

  If `result` is not tagged with `:ok`, `result` is returned as-is.

  Equivalent to `tagged_consume(result, :ok, func_or_value)`. See `tagged_consume/3`.

  ## Examples

      iex> :ok |> Result.consume()
      :none

      iex> :ok |> Result.consume(fn -> "hello" end)
      :none

      iex> :ok |> Result.consume(fn {} -> "hello" end)
      :none

      iex> {:ok, 1} |> Result.consume(fn 1 -> "hello" end)
      :none

      iex> {:ok, 1, 2} |> Result.consume(fn 1, 2 -> "hello" end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:ok, 1, 2} |> Result.consume(fn {1, 2} -> "hello" end)
      :none

      iex> :error |> Result.consume(fn {} -> "hello" end)
      :error

      iex> {:error, 1} |> Result.consume(fn 1 -> "hello" end)
      {:error, 1}

      iex> "bare value" |> Result.consume()
      "bare value"
  """
  @spec consume(result_input(), (any() -> any())) :: out when out: any()
  def consume(result, func_or_value \\ & &1),
    do: tagged_consume(result, :ok, func_or_value)

  @doc section: :error_functions
  @doc """
  If `result` is tagged with `:error`, passes the wrapped value into the provided function (if
  provided) and returns `:none`.

  If `result` is not tagged with `:error`, `result` is returned as-is.

  Equivalent to `tagged_consume(result, :error, func_or_value)`. See `tagged_consume/3`.

  ## Examples

      iex> :error |> Result.error_consume()
      :none

      iex> :error |> Result.error_consume(fn -> "hello" end)
      :none

      iex> :error |> Result.error_consume(fn {} -> "hello" end)
      :none

      iex> {:error, 1} |> Result.error_consume(fn 1 -> "hello" end)
      :none

      iex> {:error, 1, 2} |> Result.error_consume(fn 1, 2 -> "hello" end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:error, 1, 2} |> Result.error_consume(fn {1, 2} -> "hello" end)
      :none

      iex> :ok |> Result.error_consume(fn {} -> "hello" end)
      :ok

      iex> {:ok, 1} |> Result.error_consume(fn 1 -> "hello" end)
      {:ok, 1}

      iex> "bare value" |> Result.error_consume()
      "bare value"
  """
  @spec error_consume(result_input(), (any() -> any())) :: out when out: any()
  def error_consume(result, func_or_value \\ & &1),
    do: tagged_consume(result, :error, func_or_value)

  @doc section: :generic_functions
  @doc """
  If `result` is tagged with the specified `tag` atom, passes the wrapped value into the provided
  function (if provided) and returns `:none`.

  If `result` is not tagged with the specified `tag` atom, `result` is returned as-is.

  ## Examples

      iex> :ok |> Result.tagged_consume(:ok)
      :none

      iex> :error |> Result.tagged_consume(:error, fn -> "hello" end)
      :none

      iex> :error |> Result.tagged_consume(:error, fn {} -> "hello" end)
      :none

      iex> {:some, 1} |> Result.tagged_consume(:some, fn 1 -> "hello" end)
      :none

      iex> {:ok, 1, 2} |> Result.tagged_consume(:ok, fn 1, 2 -> "hello" end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:ok, 1, 2} |> Result.tagged_consume(:ok, fn {1, 2} -> "hello" end)
      :none

      iex> :error |> Result.tagged_consume(:ok, fn {} -> "hello" end)
      :error

      iex> {:error, 1} |> Result.tagged_consume(:ok, fn 1 -> "hello" end)
      {:error, 1}

      iex> "bare value" |> Result.tagged_consume(:ok)
      "bare value"
  """
  @spec tagged_consume(result_input(), atom(), (any() -> any())) :: out when out: any()
  def tagged_consume(result, tag, function \\ & &1)
      when is_atom(tag) and is_function(function) do
    tagged_then(result, tag, fn value ->
      Private.map_value(value, function)
      :none
    end)
  end

  @doc section: :none_functions
  @doc """
  If `result` is tagged `:none`, returns `func_or_value` wrapped as an `:ok` result. Otherwise,
  returns `result`. If `func_or_value` is a function, the returned value is used as the new value.

  If the new value is `nil`, then the result will remain `:none`. Consider using `none_then/2` if
  you don't want this behaviour.

  If `result` is not tagged `:none`, `result` is returned as-is.

  Equivalent to `default_as(result, :ok, func_or_value)`. See `default_as/3`.

  ## Examples

      iex> :none |> Result.default("hello")
      {:ok, "hello"}

      iex> :none |> Result.default({})
      :ok

      iex> :none |> Result.default(nil)
      :none

      iex> :none |> Result.default(fn -> 1 end)
      {:ok, 1}

      iex> :none |> Result.default(fn {} -> 1 end)
      {:ok, 1}

      iex> {:none, 1} |> Result.default(& &1)
      {:ok, 1}

      iex> :ok |> Result.default("hello")
      :ok

      iex> {:ok, 1} |> Result.default("hello")
      {:ok, 1}

      iex> {:ok, 1, 2} |> Result.default("hello")
      {:ok, 1, 2}

      iex> {:anything, 1} |> Result.default("hello")
      {:anything, 1}

      iex> "bare value" |> Result.default("hello")
      "bare value"
  """
  @spec default(input, (() -> out) | out) :: input | :ok | ok(out)
        when input: result_input(), out: any()
  def default(result, func_or_value), do: default_as(result, :ok, func_or_value)

  @doc section: :none_functions
  @doc """
  If `result` is tagged `:none`, returns `func_or_value` wrapped as an `:error` result. Otherwise,
  returns `result`. If `func_or_value` is a function, the returned value is used as the new value.

  If the new value is `nil`, then the result will remain `:none`. Consider using `none_then/2` if
  you don't want this behaviour.

  If `result` is not tagged `:none`, `result` is returned as-is.

  Equivalent to `default_as(result, :error, func_or_value)`. See `default_as/3`.

  ## Examples

      iex> :none |> Result.default_error("hello")
      {:error, "hello"}

      iex> :none |> Result.default_error({})
      :error

      iex> :none |> Result.default_error(nil)
      :none

      iex> :none |> Result.default_error(fn -> 1 end)
      {:error, 1}

      iex> :none |> Result.default_error(fn {} -> 1 end)
      {:error, 1}

      iex> {:none, 1} |> Result.default_error(& &1)
      {:error, 1}

      iex> :error |> Result.default_error("hello")
      :error

      iex> {:error, 1} |> Result.default_error("hello")
      {:error, 1}

      iex> {:error, 1, 2} |> Result.default_error("hello")
      {:error, 1, 2}

      iex> {:anything, 1} |> Result.default_error("hello")
      {:anything, 1}

      iex> "bare value" |> Result.default_error("hello")
      "bare value"
  """
  @spec default_error(input, (() -> out) | out) :: input | :error | error(out)
        when input: result_input(), out: any()
  def default_error(result, func_or_value), do: default_as(result, :error, func_or_value)

  @doc section: :none_functions
  @doc """
  If `result` is tagged `:none`, returns `func_or_value` wrapped as a result with the given `tag`.
  Otherwise, returns `result`. If `func_or_value` is a function, the returned value is used as the
  new value.

  If the new value is `nil`, then the result will remain `:none`. Consider using `none_then/2` if
  you don't want this behaviour.

  If `result` is not tagged `:none`, `result` is returned as-is.

  ## Examples

      iex> :none |> Result.default_as(:ok, "hello")
      {:ok, "hello"}

      iex> :none |> Result.default_as(:error, {})
      :error

      iex> :none |> Result.default_as(:something, nil)
      :none

      iex> :none |> Result.default_as(:ok, fn -> 1 end)
      {:ok, 1}

      iex> :none |> Result.default_as(:ok, fn {} -> 1 end)
      {:ok, 1}

      iex> {:none, 1} |> Result.default_as(:ok, & &1)
      {:ok, 1}

      iex> :ok |> Result.default_as(:ok, "hello")
      :ok

      iex> {:ok, 1} |> Result.default_as(:ok, "hello")
      {:ok, 1}

      iex> {:ok, 1, 2} |> Result.default_as(:ok, "hello")
      {:ok, 1, 2}

      iex> {:anything, 1} |> Result.default_as(:ok, "hello")
      {:anything, 1}

      iex> "bare value" |> Result.default_as(:ok, "hello")
      "bare value"
  """
  @spec default_as(input, tag, (() -> out) | out) :: input | tag | {tag, out}
        when input: result_input(), tag: atom(), out: any()
  def default_as(result, tag, func_or_value) when Private.is_tag(tag) do
    result
    |> none_then(fn value ->
      Private.map_value(value, func_or_value)
      |> from_as(tag)
    end)
  end

  @doc section: :ok_functions
  @doc """
  If `result` is tagged `:ok`, passes the wrapped value into the provided function. If
  `check_function` returns a truthy value, `result` is returned unchanged. Otherwise, returns
  `:none`.

  Equivalent to `tagged_filter(result, :ok, check_function)`. See `tagged_filter/3`.

  ## Examples

      iex> {:ok, "hello"} |> Result.filter(&String.length(&1) == 5)
      {:ok, "hello"}

      iex> {:ok, "hello"} |> Result.filter(&String.length(&1) == 0)
      :none

      iex> :some |> Result.filter(&String.length(&1) == 0)
      :some

      iex> :error |> Result.filter(&String.length(&1) == 0)
      :error

      iex> nil |> Result.filter(&String.length(&1) == 0)
      nil
  """
  @spec filter(result_input(), (any() -> as_boolean(any()))) :: result_input()
  def filter(result, check_function) when is_function(check_function, 1),
    do: tagged_filter(result, :ok, check_function)

  @doc section: :error_functions
  @doc """
  If `result` is tagged `:error`, passes the wrapped value into the provided function. If
  `check_function` returns a truthy value, `result` is returned unchanged. Otherwise, returns
  `:none`.

  Equivalent to `tagged_filter(result, :error, check_function)`. See `tagged_filter/3`.

  ## Examples

      iex> {:error, "hello"} |> Result.error_filter(&String.length(&1) == 5)
      {:error, "hello"}

      iex> {:error, "hello"} |> Result.error_filter(&String.length(&1) == 0)
      :none

      iex> :some |> Result.error_filter(&String.length(&1) == 0)
      :some

      iex> :ok |> Result.error_filter(&String.length(&1) == 0)
      :ok

      iex> nil |> Result.error_filter(&String.length(&1) == 0)
      nil
  """
  @spec error_filter(result_input(), (any() -> as_boolean(any()))) :: result_input()
  def error_filter(result, check_function) when is_function(check_function, 1),
    do: tagged_filter(result, :error, check_function)

  @doc section: :generic_functions
  @doc """
  If `result` is tagged with the specified `tag` atom, passes the wrapped value into the provided
  function. If `check_function` returns a truthy value, `result` is returned unchanged. Otherwise,
  returns `:none`.

  ## Examples

      iex> {:ok, "hello"} |> Result.tagged_filter(:ok, &String.length(&1) == 5)
      {:ok, "hello"}

      iex> {:ok, "hello"} |> Result.tagged_filter(:ok, &String.length(&1) == 0)
      :none

      iex> :some |> Result.tagged_filter(:ok, &String.length(&1) == 0)
      :some

      iex> :error |> Result.tagged_filter(:ok, &String.length(&1) == 0)
      :error

      iex> nil |> Result.tagged_filter(:ok, &String.length(&1) == 0)
      nil
  """
  @spec tagged_filter(result_input(), atom(), (any() -> as_boolean(any()))) :: result_input()
  def tagged_filter(result, tag, check_function) when is_function(check_function, 1) do
    tagged_then(result, tag, fn value ->
      if check_function.(value) do
        result
      else
        :none
      end
    end)
  end

  @doc """
  Converts `value` into a `maybe_is(tag)` result: `{atom(), any()} | :none`

  If `value` is `nil`, then the result will be `:none`. See also `from_as!/2`.

  Otherwise, the result will be a two-element tuple, where the first element is the provided tag,
  and the second element is `value`.

  ## Examples

      iex> "hello" |> Result.from_as(:ok)
      {:ok, "hello"}

      iex> Result.from_as({1, 2}, :something)
      {:something, {1, 2}}

      iex> Result.from_as({}, :any_atom)
      :any_atom

      iex> Result.from_as(nil, :ok)
      :none
  """
  @spec from_as(v, atom()) :: maybe_is(v) when v: any()
  def from_as(nil, tag) when Private.is_tag(tag), do: :none

  def from_as(value, tag) when Private.is_tag(tag) do
    {tag, value}
    |> Private.normalize_result_output()
  end

  @doc """
  Same as `from_as/2`, except raises `ArgumentError` if `value` is `nil`.

  ## Examples

      iex> "hello" |> Result.from_as!(:ok)
      {:ok, "hello"}

      iex> nil |> Result.from_as!(:ok)
      ** (ArgumentError) Value is nil.
  """
  @spec from_as!(v, atom()) :: maybe_is(v) when v: any()
  def from_as!(nil, tag) when Private.is_tag(tag), do: raise(ArgumentError, "Value is nil.")
  def from_as!(value, tag) when Private.is_tag(tag), do: from_as(value, tag)

  @doc """
  Converts `value` into a `maybe(v)` result: `{:ok, value} | :none`

  If `value` is `nil`, then the result will be `:none`. See also `from!/1`.

  Otherwise, the result will be a two-element tuple, where the first element is `:ok`, and the
  second element is `value`.

  ## Examples

      iex> Result.from("hello")
      {:ok, "hello"}

      iex> Result.from({1, 2})
      {:ok, {1, 2}}

      iex> Result.from({})
      :ok

      iex> Result.from(nil)
      :none
  """
  @spec from(v) :: maybe(v) when v: any()
  def from(value), do: from_as(value, :ok)

  @doc """
  Same as `from/1`, except raises `ArgumentError` if `value` is `nil`.

  ## Examples

      iex> Result.from!("hello")
      {:ok, "hello"}

      iex> Result.from!({1, 2})
      {:ok, {1, 2}}

      iex> Result.from!(nil)
      ** (ArgumentError) Value is nil.
  """
  @spec from!(t) :: ok(t) when t: any()
  def from!(value), do: from_as!(value, :ok)

  @doc """
  Converts `value` into a `maybe_error(e)` result: `{:error, value} | :none`

  If `value` is `nil`, then the result will be `:none`. See also `from_error!/1`.

  Otherwise, the result will be a two-element tuple, where the first element is `:error`, and the
  second element is `value`.

  ## Examples

      iex> Result.from_error("hello")
      {:error, "hello"}

      iex> Result.from_error({1, 2})
      {:error, {1, 2}}

      iex> Result.from_error({})
      :error

      iex> Result.from_error(nil)
      :none
  """
  @spec from_error(e) :: maybe_error(e) when e: any()
  def from_error(value), do: from_as(value, :error)

  @doc """
  Same as `from_error/1`, except raises `ArgumentError` if `value` is `nil`.

  ## Examples

      iex> Result.from_error!("hello")
      {:error, "hello"}

      iex> Result.from_error!({1, 2})
      {:error, {1, 2}}

      iex> Result.from_error!(nil)
      ** (ArgumentError) Value is nil.
  """
  @spec from_error!(e) :: error(e) when e: any()
  def from_error!(value), do: from_as!(value, :error)

  @doc section: :ok_functions
  @doc """
  If `result` is tagged `:ok`, transforms the wrapped value by passing it into the provided
  mapping function, and replacing it with the returned value. If `func_or_value` is not a
  function, then it is used directly as the new value.

  If the new value would be `nil`, then `:none` is returned as the result instead. Consider piping
  into `|> none_then({:ok, nil})` if you _really_ want `{:ok, nil}`. See `none_then/2`.

  If `result` is not tagged `:ok`, `result` is returned as-is.

  Equivalent to `tagged_map(result, :ok, func_or_value)`. See `tagged_map/3`.

  ## Examples

      iex> :ok |> Result.map("hello")
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.map("hello")
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.map(nil)
      :none

      iex> :none |> Result.map("hello")
      :none

      iex> :ok |> Result.map(fn {} -> "hello" end)
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.map(fn 1 -> "hello" end)
      {:ok, "hello"}

      iex> {:ok, 1, 2} |> Result.map(fn {1, 2} -> "hello" end)
      {:ok, "hello"}

      iex> {:ok, 1, 2} |> Result.map(fn 1, 2 -> "hello" end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:ok, 1, 2} |> Result.map(fn {1, 2} -> {} end)
      :ok

      iex> :error |> Result.map(fn _ -> "hello" end)
      :error

      iex> {:error, 1} |> Result.map(fn _ -> "hello" end)
      {:error, 1}

      iex> {:error, 1, 2} |> Result.map(fn _ -> "hello" end)
      {:error, 1, 2}

      iex> :none |> Result.map(fn _ -> "hello" end)
      :none

      iex> :something_else |> Result.map(fn _ -> "hello" end)
      :something_else

      iex> "bare value" |> Result.map(fn _ -> "hello" end)
      "bare value"

      iex> "bare value" |> Result.map("hello")
      "bare value"
  """
  @spec map(t, func_or_value(out)) :: t | :ok | ok(out) when t: result_input(), out: any()
  def map(result, func_or_value), do: tagged_map(result, :ok, func_or_value)

  @doc section: :error_functions
  @doc """
  If `result` is tagged `:error`, transforms the wrapped value by passing it into the provided
  mapping function, and replacing it with the returned value. If `func_or_value` is not a
  function, then it is used directly as the new value.

  If the new value would be `nil`, then `:none` is returned as the result instead. Consider piping
  into `|> none_then({:error, nil})` if you _really_ want `{:error, nil}`. See `none_then/2`.

  If `result` is not tagged `:error`, `result` is returned as-is.

  Equivalent to `tagged_map(result, :error, func_or_value)`. See `tagged_map/3`.

  ## Examples

      iex> :error |> Result.error_map("hello")
      {:error, "hello"}

      iex> {:error, 1} |> Result.error_map("hello")
      {:error, "hello"}

      iex> {:error, 1} |> Result.error_map(nil)
      :none

      iex> :none |> Result.error_map("hello")
      :none

      iex> :error |> Result.error_map(fn {} -> "hello" end)
      {:error, "hello"}

      iex> {:error, 1} |> Result.error_map(fn 1 -> "hello" end)
      {:error, "hello"}

      iex> {:error, 1, 2} |> Result.error_map(fn {1, 2} -> "hello" end)
      {:error, "hello"}

      iex> {:error, 1, 2} |> Result.error_map(fn 1, 2 -> "hello" end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:error, 1, 2} |> Result.error_map(fn {1, 2} -> {} end)
      :error

      iex> :ok |> Result.error_map(fn _ -> "hello" end)
      :ok

      iex> {:ok, 1} |> Result.error_map(fn _ -> "hello" end)
      {:ok, 1}

      iex> {:ok, 1, 2} |> Result.error_map(fn _ -> "hello" end)
      {:ok, 1, 2}

      iex> :none |> Result.error_map(fn _ -> "hello" end)
      :none

      iex> :something_else |> Result.error_map(fn _ -> "hello" end)
      :something_else

      iex> "bare value" |> Result.error_map(fn _ -> "hello" end)
      "bare value"

      iex> "bare value" |> Result.error_map("hello")
      "bare value"
  """
  @spec error_map(t, func_or_value(out)) :: t | :error | error(out)
        when t: result_input(), out: any()
  def error_map(result, func_or_value), do: tagged_map(result, :error, func_or_value)

  @doc section: :generic_functions
  @doc """
  If `result` is tagged with the specified `tag` atom, transforms the wrapped value by passing it
  into the provided mapping function, and replacing it with the returned value. If a function is
  not provided, the argument at the same position is used as the new value.

  If the new value would be `nil`, then `:none` is returned as the result instead. Consider piping
  into `|> none_then({tag, nil})` if you _really_ want `{tag, nil}`. See `none_then/2`.

  If `result` is not tagged with the specified `tag` atom, `result` is returned as-is.

  ## Examples

      iex> :ok |> Result.tagged_map(:ok, "hello")
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.tagged_map(:ok, "hello")
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.tagged_map(:ok, nil)
      :none

      iex> :none |> Result.tagged_map(:ok, "hello")
      :none

      iex> :ok |> Result.tagged_map(:ok, fn -> "hello" end)
      {:ok, "hello"}

      iex> :ok |> Result.tagged_map(:ok, fn {} -> "hello" end)
      {:ok, "hello"}

      iex> {:bla, 1} |> Result.tagged_map(:bla, fn 1 -> "hello" end)
      {:bla, "hello"}

      iex> {:some, 1, 2} |> Result.tagged_map(:some, fn {1, 2} -> "hello" end)
      {:some, "hello"}

      iex> {:ok, 1, 2} |> Result.tagged_map(:ok, fn 1, 2 -> "hello" end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:ok, 1, 2} |> Result.tagged_map(:ok, fn {1, 2} -> {} end)
      :ok

      iex> :error |> Result.tagged_map(:ok, fn _ -> "hello" end)
      :error

      iex> {:error, 1} |> Result.tagged_map(:ok, fn _ -> "hello" end)
      {:error, 1}

      iex> {:error, 1, 2} |> Result.tagged_map(:ok, fn _ -> "hello" end)
      {:error, 1, 2}

      iex> :none |> Result.tagged_map(:ok, fn _ -> "hello" end)
      :none

      iex> :something_else |> Result.tagged_map(:ok, fn _ -> "hello" end)
      :something_else

      iex> "bare value" |> Result.tagged_map(:ok, fn _ -> "hello" end)
      "bare value"

      iex> "bare value" |> Result.tagged_map(:untagged, fn _ -> "hello" end)
      {:untagged, "hello"}

      iex> "bare value" |> Result.tagged_map(:ok, "hello")
      "bare value"

      iex> "bare value" |> Result.tagged_map(:untagged, "hello")
      {:untagged, "hello"}
  """
  @spec tagged_map(t, tag, func_or_value(out)) :: t | tag | {tag, out}
        when t: result_input(), tag: atom(), out: any()
  def tagged_map(result, tag, func_or_value) do
    normalized_result = Private.normalize_result_input(result)

    if is_tagged(normalized_result, tag) do
      normalized_result
      |> Tuple.delete_at(0)
      |> Private.normalize_value()
      |> Private.map_value(func_or_value)
      |> from_as(tag)
    else
      result
    end
  end

  @doc """
  Converts `result` from a variety of accepted result-like terms into an atom or a two-element
  tagged tuple.

  If `result` is not a tagged tuple, it is wrapped as a new result

  ## Examples

      iex> Result.normalize(:ok)
      :ok

      iex> Result.normalize({:ok, "hello"})
      {:ok, "hello"}

      iex> Result.normalize({:ok, 1, 2})
      {:ok, {1, 2}}

      iex> Result.normalize(:error)
      :error

      iex> Result.normalize({:error, "hello"})
      {:error, "hello"}

      iex> Result.normalize({:error, 1, 2})
      {:error, {1, 2}}

      iex> Result.normalize(:none)
      :none

      iex> Result.normalize({:strange, ["hello", 1, 2]})
      {:strange, ["hello", 1, 2]}

      iex> Result.normalize("hello")
      {:untagged, "hello"}

      iex> Result.normalize({1, 2})
      {:untagged, {1, 2}}

      iex> Result.normalize({})
      :untagged

      iex> Result.normalize({1, 2}, :error)
      {:error, {1, 2}}

      iex> Result.normalize(nil)
      :none

      iex> Result.normalize(nil, :error)
      :none
  """
  @spec normalize(result_input(), atom()) :: tagged()
  def normalize(result, default_tag \\ :untagged) when Private.is_tag(default_tag) do
    result
    |> Private.normalize_result_input(default_tag)
    |> Private.normalize_result_output()
  end

  @doc """
  Same as `normalize/1`, except raises `ArgumentError` if `value` is untagged.

  ## Examples

      iex> Result.normalize({:ok, "hello"})
      {:ok, "hello"}

      iex> Result.normalize!("hello")
      ** (ArgumentError) Result is untagged: "hello"
  """
  @spec normalize!(result_input()) :: tagged()
  def normalize!(result) do
    normalize(result)
    |> case do
      {:untagged, value} -> raise(ArgumentError, "Result is untagged: #{Kernel.inspect(value)}")
      tuple -> tuple
    end
  end

  @doc section: :ok_functions
  @doc """
  If `result` is _not_ tagged with `:ok`, passes the tag and wrapped value into the provided
  function and returns the result. If the function has arity 1, then only the wrapped value is
  passed in. If `func_or_value` is not a function, then it is used directly as the new value.

  If `result` _is_ tagged with `:ok`, `result` is returned as-is.

  Use this function in a pipeline to branch the unhappy path into another function, or as a kind
  of `case` expression to handle multiple types of result without the boilerplate of copying
  through a successful result.

  Be aware that no attempt is made to ensure the return value from the function is a tagged tuple.
  However, all functions are tolerant of untagged results, and on input will interpret them as an
  `{:untagged, value}` tuple.

  Equivalent to `tagged_or_else(result, :ok, func_or_value)`. See `tagged_or_else/3`.

  ## Examples

      iex> :error
      ...> |> Result.or_else(fn
      ...>   :error, {} -> {:ok, "hello"}
      ...> end)
      {:ok, "hello"}

      iex> {:error, 1}
      ...> |> Result.or_else(fn
      ...>   :error, 1 -> {:ok, "hello"}
      ...> end)
      {:ok, "hello"}

      iex> {:error, 1, 2}
      ...> |> Result.or_else(fn
      ...>   :error, {1, 2} -> {:ok, "matched error"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:ok, "matched error"}

      iex> :none
      ...> |> Result.or_else(fn
      ...>   :error, {1, 2} -> {:ok, "matched error"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:ok, "matched none"}

      iex> {:ok, "just ok"}
      ...> |> Result.or_else(fn
      ...>   :error, {1, 2} -> {:error, "matched error"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:ok, "just ok"}

      iex> {:error, 1, 2}
      ...> |> Result.or_else(fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched two terms"}

      iex> {:error, 1}
      ...> |> Result.or_else(fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched one term"}

      iex> :error
      ...> |> Result.or_else(fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched no terms"}

      iex> :none
      ...> |> Result.or_else(fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched no terms"}

      iex> :error |> Result.or_else({:ok, "hello"})
      {:ok, "hello"}

      iex> {:error, 1} |> Result.or_else({:ok, "hello"})
      {:ok, "hello"}

      iex> {:error, 1} |> Result.or_else("bare value")
      "bare value"

      iex> "bare value" |> Result.or_else(fn _ -> :none end)
      :none

      iex> "bare value" |> Result.or_else(fn
      ...>  :untagged, "bare value" -> :none
      ...> end)
      :none
  """
  @spec or_else(result_input(), func_or_value(atom(), out)) :: out when out: any()
  def or_else(result, func_or_value), do: tagged_or_else(result, :ok, func_or_value)

  @doc section: :error_functions
  @doc """
  If `result` is _not_ tagged with `:error`, passes the tag and wrapped value into the provided
  function and returns the result. If the function has arity 1, then only the wrapped value is
  passed in. If `func_or_value` is not a function, then it is used directly as the new value.

  If `result` _is_ tagged with `:error`, `result` is returned as-is.

  Use this function in a pipeline to branch the happy path into another function, or as a kind of
  `case` expression to handle multiple types of result without the boilerplate of copying through
  an error result.

  Be aware that no attempt is made to ensure the return value from the function is a tagged tuple.
  However, all functions are tolerant of untagged results, and on input will interpret them as an
  `{:untagged, value}` tuple.

  Equivalent to `tagged_or_else(result, :error, func_or_value)`. See `tagged_or_else/3`.

  ## Examples

      iex> :ok
      ...> |> Result.error_or_else(fn
      ...>   :ok, {} -> {:ok, "hello"}
      ...> end)
      {:ok, "hello"}

      iex> {:ok, 1}
      ...> |> Result.error_or_else(fn
      ...>   :ok, 1 -> {:ok, "hello"}
      ...> end)
      {:ok, "hello"}

      iex> {:ok, 1, 2}
      ...> |> Result.error_or_else(fn
      ...>   :ok, {1, 2} -> {:ok, "matched ok"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:ok, "matched ok"}

      iex> :none
      ...> |> Result.error_or_else(fn
      ...>   :ok, {1, 2} -> {:ok, "matched ok"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:ok, "matched none"}

      iex> {:error, "just error"}
      ...> |> Result.error_or_else(fn
      ...>   :ok, {1, 2} -> {:ok, "matched ok"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:error, "just error"}

      iex> {:ok, 1, 2}
      ...> |> Result.error_or_else(fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched two terms"}

      iex> {:ok, 1}
      ...> |> Result.error_or_else(fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched one term"}

      iex> :ok
      ...> |> Result.error_or_else(fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched no terms"}

      iex> :none
      ...> |> Result.error_or_else(fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched no terms"}

      iex> :ok |> Result.error_or_else({:ok, "hello"})
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.error_or_else({:ok, "hello"})
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.error_or_else("bare value")
      "bare value"

      iex> "bare value" |> Result.error_or_else(fn _ -> :none end)
      :none

      iex> "bare value" |> Result.error_or_else(fn
      ...>  :untagged, "bare value" -> :none
      ...> end)
      :none
  """
  @spec error_or_else(result_input(), func_or_value(atom(), out)) :: out when out: any()
  def error_or_else(result, func_or_value), do: tagged_or_else(result, :error, func_or_value)

  @doc section: :generic_functions
  @doc """
  If `result` is _not_ tagged with the specified `tag` atom, passes the tag and wrapped value into
  the provided function and returns the result. If the function has arity 1, then only the wrapped
  value is passed in. An arity-0 function is also accepted. If `func_or_value` is not a function,
  then it is used directly as the new value.

  If `result` _is_ tagged with the specified `tag` atom, `result` is returned as-is.

  Use this function in a pipeline to branch away from the happy path, or as a kind of `case`
  expression to handle multiple types of result without the boilerplate of copying through a
  successful result.

  Be aware that no attempt is made to ensure the return value from the function is a tagged tuple.
  However, all functions are tolerant of untagged results, and on input will interpret them as an
  `{:untagged, value}` tuple.

  ## Examples

      iex> :error
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   :error, {} -> {:ok, "hello"}
      ...> end)
      {:ok, "hello"}

      iex> {:error, 1}
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   :error, 1 -> {:ok, "hello"}
      ...> end)
      {:ok, "hello"}

      iex> {:error, 1, 2}
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   :error, {1, 2} -> {:ok, "matched error"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:ok, "matched error"}

      iex> :none
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   :error, {1, 2} -> {:ok, "matched error"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:ok, "matched none"}

      iex> {:ok, "just ok"}
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   :error, {1, 2} -> {:ok, "matched error"}
      ...>   :none, {} -> {:ok, "matched none"}
      ...> end)
      {:ok, "just ok"}

      iex> {:error, 1, 2}
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched two terms"}

      iex> {:error, 1}
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched one term"}

      iex> :error
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched no terms"}

      iex> :none
      ...> |> Result.tagged_or_else(:ok, fn
      ...>   {1, 2} -> {:ok, "matched two terms"}
      ...>   1 -> {:ok, "matched one term"}
      ...>   {} -> {:ok, "matched no terms"}
      ...> end)
      {:ok, "matched no terms"}

      iex> :none
      ...> |> Result.tagged_or_else(:ok, fn -> {:ok, "catch-all value"} end)
      {:ok, "catch-all value"}

      iex> :error |> Result.tagged_or_else(:ok, {:ok, "hello"})
      {:ok, "hello"}

      iex> {:error, 1} |> Result.tagged_or_else(:ok, {:ok, "hello"})
      {:ok, "hello"}

      iex> {:error, 1} |> Result.tagged_or_else(:ok, "bare value")
      "bare value"

      iex> "bare value" |> Result.tagged_or_else(:ok, fn _ -> :none end)
      :none

      iex> "bare value" |> Result.tagged_or_else(:ok, fn
      ...>  :untagged, "bare value" -> :none
      ...> end)
      :none

      iex> "bare value" |> Result.tagged_or_else(:untagged, fn _ -> :none end)
      "bare value"
  """
  @spec tagged_or_else(result_input(), atom(), func_or_value(atom(), out)) :: out when out: any()
  def tagged_or_else(result, tag, func_or_value) do
    normalized_result = Private.normalize_result_input(result)

    if is_tagged(normalized_result, tag) do
      result
    else
      Private.map_normalized_result(normalized_result, func_or_value)
    end
  end

  @doc section: :ok_functions
  @doc """
  If `result` is tagged `:ok`, replaces the tag with `new_tag`, returning a new tagged tuple.

  Equivalent to `tagged_retag(result, :ok, new_tag)`. See `tagged_retag/3`.

  ## Examples

      iex> :ok |> Result.retag(:none)
      :none

      iex> {:ok, "hello"} |> Result.retag(:error)
      {:error, "hello"}

      iex> {:ok, 1, 2} |> Result.retag(:error)
      {:error, {1, 2}}

      iex> {:error, 1, 2} |> Result.retag(:ok)
      {:error, 1, 2}

      iex> :ok |> Result.retag("string")
      ** (ArgumentError) Expected atom as new tag, got: "string".

      iex> "bare value" |> Result.error_retag(:error)
      "bare value"
  """
  @spec retag(result_input(), new_tag) :: new_tag | {new_tag, any()} when new_tag: atom()
  def retag(result, new_tag), do: tagged_retag(result, :ok, new_tag)

  @doc section: :error_functions
  @doc """
  If `result` is tagged `:error`, replaces the tag with `new_tag`, returning a new tagged tuple.

  Equivalent to `tagged_retag(result, :error, new_tag)`. See `tagged_retag/3`.

  ## Examples

      iex> :error |> Result.error_retag(:none)
      :none

      iex> {:error, "hello"} |> Result.error_retag(:ok)
      {:ok, "hello"}

      iex> {:error, 1, 2} |> Result.error_retag(:ok)
      {:ok, {1, 2}}

      iex> {:ok, 1, 2} |> Result.error_retag(:error)
      {:ok, 1, 2}

      iex> :error |> Result.error_retag("string")
      ** (ArgumentError) Expected atom as new tag, got: "string".

      iex> "bare value" |> Result.error_retag(:ok)
      "bare value"
  """
  @spec error_retag(result_input(), new_tag) :: new_tag | {new_tag, any()} when new_tag: atom()
  def error_retag(result, new_tag), do: tagged_retag(result, :error, new_tag)

  @doc section: :none_functions
  @doc """
  If `result` is tagged `:none`, replaces the tag with `new_tag`.

  Equivalent to `tagged_retag(result, :none, new_tag)`. See `tagged_retag/3`.

  ## Examples

      iex> :none |> Result.none_retag(:ok)
      :ok

      iex> :error |> Result.none_retag(:ok)
      :error

      iex> :ok |> Result.none_retag(:ok)
      :ok

      iex> :none |> Result.none_retag("string")
      ** (ArgumentError) Expected atom as new tag, got: "string".

      iex> "bare value" |> Result.none_retag(:error)
      "bare value"
  """
  @spec none_retag(result_input(), new_tag) :: new_tag | {new_tag, any()} when new_tag: atom()
  def none_retag(result, new_tag), do: tagged_retag(result, :none, new_tag)

  @doc section: :generic_functions
  @doc """
  If `result` is tagged with the specified `tag` atom, replaces the tag with `new_tag`, returning
  a new tagged tuple.

  ## Examples

      iex> :ok |> Result.tagged_retag(:ok, :none)
      :none

      iex> {:ok, "hello"} |> Result.tagged_retag(:ok, :error)
      {:error, "hello"}

      iex> {:error, 1, 2} |> Result.tagged_retag(:error, :ok)
      {:ok, {1, 2}}

      iex> {:ok, 1, 2} |> Result.tagged_retag(:error, :ok)
      {:ok, 1, 2}

      iex> :ok |> Result.tagged_retag(:ok, "string")
      ** (ArgumentError) Expected atom as new tag, got: "string".

      iex> "bare value" |> Result.tagged_retag(:ok, :error)
      "bare value"

      iex> "bare value" |> Result.tagged_retag(:untagged, :error)
      {:error, "bare value"}
  """
  @spec tagged_retag(result_input(), atom(), new_tag) :: new_tag | {new_tag, any()}
        when new_tag: atom()
  def tagged_retag(result, tag, new_tag) when Private.is_tag(new_tag) do
    normalized_result = Private.normalize_result_input(result)

    if is_tagged(normalized_result, tag) do
      normalized_result
      |> case do
        {^tag, value} -> {new_tag, value}
      end
      |> Private.normalize_result_output()
    else
      result
    end
  end

  def tagged_retag(_result, _tag, new_tag) do
    raise(ArgumentError, "Expected atom as new tag, got: #{Kernel.inspect(new_tag)}.")
  end

  @doc section: :ok_functions
  @doc """
  If `result` is tagged `:ok`, passes the wrapped value into `func_or_value` and returns the
  result. If a function is not provided, the argument at the same position is returned as-is.

  If `result` is not tagged with the specified `tag` atom, `result` is returned as-is.

  Use this function to pipe results into functions that return tagged tuples.

  Be aware that no attempt is made to ensure the return value from the function is a tagged tuple.
  However, all functions are tolerant of untagged results, and on input will interpret them as an
  `{:untagged, value}` tuple.

  Equivalent to `tagged_then(result, :ok, func_or_value)`. See `tagged_then/3`.

  ## Examples

      iex> :ok |> Result.then({:ok, "hello"})
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.then({:ok, "hello"})
      {:ok, "hello"}

      iex> :none |> Result.then({:ok, "hello"})
      :none

      iex> :ok |> Result.then(fn {} -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.then(fn 1 -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:ok, 1, 2} |> Result.then(fn {1, 2} -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:ok, 1, 2} |> Result.then(fn 1, 2 -> {:ok, "hello"} end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:ok, 1, 2} |> Result.then(fn {1, 2} -> :ok end)
      :ok

      iex> :error |> Result.then(fn _ -> {:ok, "hello"} end)
      :error

      iex> {:error, 1} |> Result.then(fn _ -> {:ok, "hello"} end)
      {:error, 1}

      iex> {:error, 1, 2} |> Result.then(fn _ -> {:ok, "hello"} end)
      {:error, 1, 2}

      iex> :none |> Result.then(fn _ -> {:ok, "hello"} end)
      :none

      iex> :something_else |> Result.then(fn _ -> {:ok, "hello"} end)
      :something_else

      iex> "bare value" |> Result.then({:ok, "hello"})
      "bare value"

      iex> "bare value" |> Result.then(fn _ -> {:ok, "hello"} end)
      "bare value"
  """
  @spec then(result_input(), func_or_value(out)) :: out when out: any()
  def then(result, func_or_value), do: tagged_then(result, :ok, func_or_value)

  @doc section: :error_functions
  @doc """
  If `result` is tagged `:error`, passes the wrapped value into `func_or_value` and returns the
  result. If a function is not provided, the argument at the same position is returned as-is.

  If `result` is not tagged with the specified `tag` atom, `result` is returned as-is.

  Use this function to pipe results into functions that return tagged tuples.

  Be aware that no attempt is made to ensure the return value from the function is a tagged tuple.
  However, all functions are tolerant of untagged results, and on input will interpret them as an
  `{:untagged, value}` tuple.

  Equivalent to `tagged_then(result, :error, func_or_value)`. See `tagged_then/3`.

  ## Examples

      iex> :error |> Result.error_then({:ok, "hello"})
      {:ok, "hello"}

      iex> {:error, 1} |> Result.error_then({:ok, "hello"})
      {:ok, "hello"}

      iex> :none |> Result.error_then({:ok, "hello"})
      :none

      iex> :error |> Result.error_then(fn -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> :error |> Result.error_then(fn {} -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:error, 1} |> Result.error_then(fn 1 -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:error, 1, 2} |> Result.error_then(fn {1, 2} -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:error, 1, 2} |> Result.error_then(fn 1, 2 -> {:ok, "hello"} end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:error, 1, 2} |> Result.error_then(fn {1, 2} -> :ok end)
      :ok

      iex> :ok |> Result.error_then(fn _ -> {:ok, "hello"} end)
      :ok

      iex> {:ok, 1} |> Result.error_then(fn _ -> {:ok, "hello"} end)
      {:ok, 1}

      iex> {:ok, 1, 2} |> Result.error_then(fn _ -> {:ok, "hello"} end)
      {:ok, 1, 2}

      iex> :none |> Result.error_then(fn _ -> {:ok, "hello"} end)
      :none

      iex> :something_else |> Result.error_then(fn _ -> {:ok, "hello"} end)
      :something_else

      iex> "bare value" |> Result.error_then({:ok, "hello"})
      "bare value"

      iex> "bare value" |> Result.error_then(fn _ -> {:ok, "hello"} end)
      "bare value"
  """
  @spec error_then(result_input(), func_or_value(out)) :: out when out: any()
  def error_then(result, func_or_value), do: tagged_then(result, :error, func_or_value)

  @doc_unwrapped_nils """
  ## A note about unwrapped nils

  If `result` is `nil`, it is intprereted as `:none`. This may be slightly unintuitive, so if
  you're curious, this is the reason:

  Untagged results are internally wrapped as an `{:untagged, any()}` using `Result.from_as(value,
  :untagged)`, and if `value` is `nil`, the return value of `Result.from_as/2` will always be
  `:none`.
  """

  @doc section: :none_functions
  @doc """
  If `result` is tagged `:none`, calls `func_or_value` and returns the result. If `func_or_value`
  is not a function, then it is returned as-is.

  If `result` is not tagged with the specified `tag` atom, `result` is returned as-is.

  Use this function to pipe results into functions that return tagged tuples.

  Be aware that no attempt is made to ensure the return value from the function is a tagged tuple.
  However, all functions are tolerant of untagged results, and on input will interpret them as an
  `{:untagged, value}` tuple.

  Equivalent to `tagged_then(result, :none, func_or_value)`. See `tagged_then/3`.

  #{@doc_unwrapped_nils}

  ## Examples

      iex> :none |> Result.none_then(:ok)
      :ok

      iex> :none |> Result.none_then(fn {} -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> :error |> Result.none_then(fn -> {:ok, "hello"} end)
      :error

      iex> :error |> Result.none_then(fn _ -> {:ok, "hello"} end)
      :error

      iex> {:error, 1} |> Result.none_then(fn _ -> {:ok, "hello"} end)
      {:error, 1}

      iex> {:error, 1, 2} |> Result.none_then(fn _ -> {:ok, "hello"} end)
      {:error, 1, 2}

      iex> :something_else |> Result.none_then(fn _ -> {:ok, "hello"} end)
      :something_else

      iex> "bare value" |> Result.none_then(:ok)
      "bare value"

      iex> "bare value" |> Result.none_then(fn _ -> :ok end)
      "bare value"

      iex> nil |> Result.none_then(:ok)
      :ok
  """
  @spec none_then(result_input(), func_or_value(out)) :: out when out: any()
  def none_then(result, func_or_value), do: tagged_then(result, :none, func_or_value)

  @doc section: :generic_functions
  @doc """
  If `result` is tagged with the specified `tag` atom, passes the wrapped value into the provided
  function and returns the result. If `func_or_value` is not a function, then it is returned
  as-is.

  If `result` is not tagged with the specified `tag` atom, `result` is returned as-is.

  Use this function to pipe results into functions that return tagged tuples.

  Be aware that no attempt is made to ensure the return value from the function is a tagged tuple.
  However, all functions are tolerant of untagged results, and on input will interpret them as an
  `{:untagged, value}` tuple.

  #{@doc_unwrapped_nils}

  ## Examples

      iex> :ok |> Result.tagged_then(:ok, {:ok, "hello"})
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.tagged_then(:ok, {:ok, "hello"})
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.tagged_then(:ok, "bare value")
      "bare value"

      iex> :none |> Result.tagged_then(:ok, {:ok, "hello"})
      :none

      iex> :ok |> Result.tagged_then(:ok, fn -> "bare value" end)
      "bare value"

      iex> :ok |> Result.tagged_then(:ok, fn {} -> "bare value" end)
      "bare value"

      iex> :ok |> Result.tagged_then(:ok, fn {} -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:ok, 1} |> Result.tagged_then(:ok, fn 1 -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:ok, 1, 2} |> Result.tagged_then(:ok, fn {1, 2} -> {:ok, "hello"} end)
      {:ok, "hello"}

      iex> {:ok, 1, 2} |> Result.tagged_then(:ok, fn 1, 2 -> {:ok, "hello"} end)
      ** (ArgumentError) Value-mapping function must have arity between 0 and 1.

      iex> {:ok, 1, 2} |> Result.tagged_then(:ok, fn {1, 2} -> {:ok, {}} end)
      {:ok, {}}

      iex> :error |> Result.tagged_then(:ok, fn _ -> {:ok, "hello"} end)
      :error

      iex> {:error, 1} |> Result.tagged_then(:ok, fn _ -> {:ok, "hello"} end)
      {:error, 1}

      iex> {:error, 1, 2} |> Result.tagged_then(:ok, fn _ -> {:ok, "hello"} end)
      {:error, 1, 2}

      iex> :none |> Result.tagged_then(:ok, fn _ -> {:ok, "hello"} end)
      :none

      iex> :something_else |> Result.tagged_then(:ok, fn _ -> {:ok, "hello"} end)
      :something_else

      iex> "bare value" |> Result.tagged_then(:ok, fn _ -> :none end)
      "bare value"

      iex> "bare value" |> Result.tagged_then(:untagged, fn _ -> :none end)
      :none

      iex> "bare value" |> Result.tagged_then(:ok, :none)
      "bare value"

      iex> "bare value" |> Result.tagged_then(:untagged, :none)
      :none

      iex> nil |> Result.tagged_then(:none, :ok)
      :ok
  """
  @spec tagged_then(result_input(), atom(), func_or_value(out)) :: out when out: any()
  def tagged_then(result, tag, func_or_value) do
    normalized_result = Private.normalize_result_input(result)

    if is_tagged(normalized_result, tag) do
      case normalized_result do
        {^tag, value} -> Private.map_value(value, func_or_value)
      end
    else
      result
    end
  end

  @doc section: :ok_functions
  @doc """
  Returns the wrapped value if `result` is tagged `:ok`. Otherwise, passes the tag and wrapped
  value into the provided function and returns the result. If the function has arity 1, then only
  the wrapped value is passed in. An arity-0 function is also accepted. If `func_or_value` is not
  a function, then it is used directly as the new value.

  See also `tagged_or_else/3`.

  Equivalent to `tagged_unwrap_or_else(result, :ok, default)`. See `tagged_unwrap_or_else/3`.

  ## Examples

      iex> {:ok, "hello"} |> Result.unwrap_or_else("default")
      "hello"

      iex> :ok |> Result.unwrap_or_else("default")
      {}

      iex> :error |> Result.unwrap_or_else("default")
      "default"

      iex> {:error, "hello"} |> Result.unwrap_or_else("default")
      "default"

      iex> {:error, "hello"}
      ...> |> Result.unwrap_or_else(fn
      ...>   :error, "hello" -> "default"
      ...> end)
      "default"

      iex> {:error, "hello"}
      ...> |> Result.unwrap_or_else(fn
      ...>   "hello" -> "default"
      ...> end)
      "default"

      iex> {:error, "hello"} |> Result.unwrap_or_else(fn -> "default" end)
      "default"

      iex> :none |> Result.unwrap_or_else("default")
      "default"

      iex> "hello" |> Result.unwrap_or_else("default")
      "default"
  """
  @spec unwrap_or_else(result_input(), func_or_value(any())) :: any()
  def unwrap_or_else(result, func_or_value), do: tagged_unwrap_or_else(result, :ok, func_or_value)

  @doc section: :ok_functions
  @doc """
  Same as `unwrap_or_else/2`, except raises `ArgumentError` if `result` is not tagged `:ok`.

  ## Examples

      iex> {:ok, "hello"} |> Result.unwrap!()
      "hello"

      iex> :ok |> Result.unwrap!()
      {}

      iex> :error |> Result.unwrap!()
      ** (ArgumentError) Result is not tagged ok: :error.

      iex> {:error, "hello"} |> Result.unwrap!()
      ** (ArgumentError) Result is not tagged ok: {:error, "hello"}.

      iex> :none |> Result.unwrap!()
      ** (ArgumentError) Result is not tagged ok: :none.

      iex> "hello" |> Result.unwrap!()
      ** (ArgumentError) Result is not tagged ok: "hello".
  """
  @spec unwrap!(result_input()) :: any()
  def unwrap!(result), do: tagged_unwrap!(result, :ok)

  @doc section: :error_functions
  @doc """
  Returns the wrapped value if `result` is tagged `:error`. Otherwise, passes the tag and wrapped
  value into the provided function and returns the result. If the function has arity 1, then only
  the wrapped value is passed in. An arity-0 function is also accepted. If `func_or_value` is not
  a function, then it is used directly as the new value.

  See also `tagged_or_else/3`.

  Equivalent to `tagged_unwrap_or_else(result, :error, default)`. See `tagged_unwrap_or_else/3`.

  ## Examples

      iex> {:error, "hello"} |> Result.error_unwrap_or_else("default")
      "hello"

      iex> :error |> Result.error_unwrap_or_else("default")
      {}

      iex> :ok |> Result.error_unwrap_or_else("default")
      "default"

      iex> {:ok, "hello"} |> Result.error_unwrap_or_else("default")
      "default"

      iex> {:ok, "hello"}
      ...> |> Result.error_unwrap_or_else(fn
      ...>   :ok, "hello" -> "default"
      ...> end)
      "default"

      iex> {:ok, "hello"}
      ...> |> Result.error_unwrap_or_else(fn
      ...>   "hello" -> "default"
      ...> end)
      "default"

      iex> {:error, "hello"} |> Result.tagged_unwrap_or_else(:ok, fn -> "default" end)
      "default"

      iex> :none |> Result.error_unwrap_or_else("default")
      "default"

      iex> "hello" |> Result.error_unwrap_or_else("default")
      "default"
  """
  @spec error_unwrap_or_else(result_input(), func_or_value(any())) :: any()
  def error_unwrap_or_else(result, func_or_value),
    do: tagged_unwrap_or_else(result, :error, func_or_value)

  @doc section: :error_functions
  @doc """
  Same as `error_unwrap_or_else/2`, except raises `ArgumentError` if `result` is not tagged
  `:error`.

  ## Examples

      iex> {:error, "hello"} |> Result.error_unwrap!()
      "hello"

      iex> :error |> Result.error_unwrap!()
      {}

      iex> :ok |> Result.error_unwrap!()
      ** (ArgumentError) Result is not tagged error: :ok.

      iex> {:ok, "hello"} |> Result.error_unwrap!()
      ** (ArgumentError) Result is not tagged error: {:ok, "hello"}.

      iex> :none |> Result.error_unwrap!()
      ** (ArgumentError) Result is not tagged error: :none.

      iex> "hello" |> Result.error_unwrap!()
      ** (ArgumentError) Result is not tagged error: "hello".
  """
  @spec error_unwrap!(result_input()) :: any()
  def error_unwrap!(result), do: tagged_unwrap!(result, :error)

  @doc section: :generic_functions
  @doc """
  Returns the wrapped value if `result` is tagged with the specified `tag` atom. Otherwise, passes
  the tag and wrapped value into the provided function and returns the result. If the function
  has arity 1, then only the wrapped value is passed in. An arity-0 function is also accepted. If
  `func_or_value` is not a function, then it is used directly as the new value.

  See also `tagged_or_else/3`.

  ## Examples

      iex> {:ok, "hello"} |> Result.tagged_unwrap_or_else(:ok, "default")
      "hello"

      iex> :some |> Result.tagged_unwrap_or_else(:some, "default")
      {}

      iex> :error |> Result.tagged_unwrap_or_else(:ok, "default")
      "default"

      iex> {:error, "hello"} |> Result.tagged_unwrap_or_else(:ok, "default")
      "default"

      iex> {:error, "hello"}
      ...> |> Result.tagged_unwrap_or_else(:ok, fn
      ...>   :error, "hello" -> "default"
      ...> end)
      "default"

      iex> {:error, "hello"}
      ...> |> Result.tagged_unwrap_or_else(:ok, fn
      ...>   "hello" -> "default"
      ...> end)
      "default"

      iex> {:error, "hello"} |> Result.tagged_unwrap_or_else(:ok, fn -> "default" end)
      "default"

      iex> :none |> Result.tagged_unwrap_or_else(:ok, "default")
      "default"

      iex> "hello" |> Result.tagged_unwrap_or_else(:ok, "default")
      "default"

      iex> "hello" |> Result.tagged_unwrap_or_else(:untagged, "default")
      "hello"
  """
  @spec tagged_unwrap_or_else(result_input(), atom(), func_or_value(any())) :: any()
  def tagged_unwrap_or_else(result, tag, func_or_value) do
    normalized_result = Private.normalize_result_input(result)

    if is_tagged(normalized_result, tag) do
      Kernel.elem(normalized_result, 1)
    else
      Private.map_normalized_result(normalized_result, func_or_value)
    end
  end

  @doc section: :generic_functions
  @doc """
  Same as `tagged_unwrap_or_else/3`, except raises `ArgumentError` if `result` is not tagged with
  the specified `tag` atom.

  ## Examples

      iex> {:ok, "hello"} |> Result.tagged_unwrap!(:ok)
      "hello"

      iex> :some |> Result.tagged_unwrap!(:some)
      {}

      iex> :error |> Result.tagged_unwrap!(:ok)
      ** (ArgumentError) Result is not tagged ok: :error.

      iex> {:ok, "hello"} |> Result.tagged_unwrap!(:error)
      ** (ArgumentError) Result is not tagged error: {:ok, "hello"}.

      iex> :none |> Result.tagged_unwrap!(:ok)
      ** (ArgumentError) Result is not tagged ok: :none.

      iex> "hello" |> Result.tagged_unwrap!(:untagged)
      "hello"

      iex> "hello" |> Result.tagged_unwrap!(:ok)
      ** (ArgumentError) Result is not tagged ok: "hello".
  """
  @spec tagged_unwrap!(result_input(), atom()) :: any()
  def tagged_unwrap!(result, tag) do
    normalized_result = Private.normalize_result_input(result)

    if is_tagged(normalized_result, tag) do
      normalized_result
      |> Tuple.delete_at(0)
      |> Private.normalize_value()
    else
      raise(ArgumentError, "Result is not tagged #{tag}: #{Kernel.inspect(result)}.")
    end
  end
end
