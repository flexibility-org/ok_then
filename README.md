# OK then...

**The Swiss Army Knife for tagged tuple pipelines**

[![Hex pm](https://img.shields.io/hexpm/v/ok_then)](https://hex.pm/packages/ok_then)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue)](https://hexdocs.pm/ok_then)
[![Test Status](https://img.shields.io/github/workflow/status/flexibility-org/ok_then/Mix%20Tests)](https://github.com/flexibility-org/ok_then/actions)

Looking for a better way to handle **errors**, **optional results**,
and **default values**? Wish there were a really **consistent** and
**full-featured** API to handle **tagged tuples** in **pipelines**?

* [How to install](#installation)
* [Why does this exist?](#why)
* [API Documentation](https://hexdocs.pm/ok_then/OkThen.Result.html)
* [Elixir Forum Thread](https://elixirforum.com/t/39983)

## At a glance

**Wrap values:**
```elixir
Result.from("hello")     # {:ok, "hello"}
Result.from(1)           # {:ok, 1}
Result.from(nil)         # :none
Result.from_error(1)     # {:error, 1}
Result.from_as(1, :some) # {:some, 1}
```

**Map values selectively by tag:**
```elixir
def pipeline(value_r) do
  value_r
  |> Result.map(& &1 * 2)
  |> Result.error_map(& {:bad_input_value, &1})
  |> Result.tagged_map(:add_2, & &1 + 2)
end

Result.from(1) |> pipeline()            # {:ok, 2}
Result.from(nil) |> pipeline()          # :none
Result.from_error(1) |> pipeline()      # {:error, {:bad_input_value, 1}}
Result.from_as(1, :add_2) |> pipeline() # {:add_2, 3}
```

**Or apply functions selectively by tag:**
```elixir
def double(value), do: {:ok, value * 2}
def error(value), do: {:error, value}

{:ok, 1} |> Result.then(&double/1) |> Result.then(&double/1)      # {:ok, 4}
{:ok, 1} |> Result.then(&error/1) |> Result.then(&double/1)       # {:error, 1}
{:ok, 1} |> Result.then(&double/1) |> Result.then(&error/1)       # {:error, 2}
{:ok, 1} |> Result.then(&error/1) |> Result.error_then(&double/1) # {:ok, 2}
```

**And handle unexpected values safely:**
```elixir
def to_nil(_value), do: nil
def error(value), do: {:error, value}

def unwrap_result(result) do
  Result.default("default")
  |> Result.unwrap_or_else("failsafe")
end

Result.from(1)           # {:ok, 1}
|> unwrap_result()       # 1

Result.from(1)           # {:ok, 1}
|> Result.map(&to_nil/1) # :none
|> unwrap_result()       # "default"

Result.from(1)           # {:ok, 1}
|> Result.then(&error/1) # {:error, 1}
|> unwrap_result()       # "failsafe"
```

**Typespecs:**
```elixir
@spec a() :: Result.ok_or(any())
@spec a() :: :ok | {:error, any()}

@spec b() :: Result.ok_or(integer(), any())
@spec b() :: {:ok, integer()} | {:error, any()}

@spec c() :: Result.maybe(integer())
@spec c() :: {:ok, integer()} | :none

@spec d() :: Result.maybe(integer(), any())
@spec d() :: {:ok, integer()} | :none | {:error, any()}
```

**You can even handle tagged tuples inside Enums:**
```elixir
# Tags other than :ok and :error are supported too :)
[{:ok, 1}, {:ok, 2}, {:ok, 3}, {:error, 4}, {:error, 5}]
|> Result.Enum.group_by_tag()
%{
  error: [4, 5],
  ok: [1, 2, 3]
}
```

```elixir
[{:ok, 1}, {:ok, 2}, {:ok, 3}]
|> Result.Enum.collect()
{:ok, [1, 2, 3]}
```

```elixir
[{:ok, 1}, {:ok, 2}, {:error, 3}, {:ok, 4}]
|> Result.Enum.collect()
{:error, 3}
```

Check out [the API documentation](https://hexdocs.pm/ok_then/OkThen.Result.html)
for a full list of supported functions, guards, and types.

## Why?

Because:

1. Remembering to **check for `nil`** is the bane of any programmer's life. It
   pops up _everywhere_.
2. **Tagged tuples**, the idiomatic solution to this problem, can become
   **verbose**, especially when they need to be passed to several functions, or
   through a pipeline.
3. Although `{:ok, value} | {:error, reason}` is ubiquitous, there is no
   standardised pattern to represent **optional values**, other than `value |
   nil`.

Failing to address point 3 leads to code that **either**:

1. Returns `{:ok, nil}`, which brings us **right back** to unexpected `nils`
   popping up in the most obscure ways:

   `** (UndefinedFunctionError) function nil.my_map_key/0 is undefined.`

2. Returns `{:error, :not_found}` or similar, which is often semantically
   questionable: missing values are often **not actually errors**. This can lead
   to confusion in determining how best to handle **fallback values** and error
   logging.

One solution (adopted by languages such as Rust), is to provide a return type
that is **explicitly optional**. In Elixir we could represent this with an
orthogonal type of tagged tuple:


```elixir
{:some, value} | :none
```

The main drawback of this approach is how verbose the tuples can become in log
output, especially when nested.

```elixir
{:ok, {:some, %MyStruct{key: "value"}}}
{:ok, :none}
{:error, {:some, "Example Error"}}
{:error, :none}   # Is this an error, or a lack of error?
```

To mitigate this issue, the approach taken by this package is to **combine** the
"ok/error" and "some/none" types into a single type of tagged tuple called a
**"maybe"**:

```elixir
{:ok, value} | :none | {:error, reason}
```

* **Specific functions** are provided to handle tagged tuples with these tags (`:ok,
  :none, :error`).
* **Generic functions** also exist to handle _any_ tag, but are slightly less
  convenient.
* Functions that _create_ or _map_ tagged tuples will **catch `nil` values** and
  transform the returned result into `:none`.

This time, we can handle an unexpected `nil` far more elegantly. Here is a
slightly contrived example:

```elixir
get_my_map()                           # nil
|> Result.from()                       # :none
|> Result.default(%{})                 # {:ok, %{}}
|> Result.map(&Map.get(:my_map_key))   # :none
|> Result.unwrap_or_else("default")    # "default"
```

And now imagine we could introduce an unexpected error. This is not altered by
`default`, which only affects results tagged `:none`. However, `unwrap_or_else`
will catch _any_ result that is not `:ok`:

```elixir
{:error, "Unexpected Error"}
|> Result.default(%{})                 # {:error, "Unexpected Error"}
|> Result.map(&Map.get(:my_map_key))   # {:error, "Unexpected Error"}
|> Result.unwrap_or_else("default")    # "default"
```

Even better, we could "consume" the error by logging it, then handle the missing
value just like before:

```elixir
{:error, "Unexpected Error"}
|> Result.error_consume(&Logger.error/1) # :none ("Unexpected Error" is logged)
|> Result.default(%{})                   # {:ok, %{}}
|> Result.map(&Map.get(:my_map_key))     # :none
|> Result.unwrap!()                      # "default"
```

Take a look at [some more examples](#at-a-glance).

## Installation

Simply add the package to your deps in `mix.exs`:

```elixir
def deps do
  [
    {:ok_then, "~> x.x.x"}  # Check "hex" badge at the top for current version
  ]
end
```
