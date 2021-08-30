defmodule OkThen.ResultTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias OkThen.Result
  require Result

  import ExUnit.CaptureIO

  doctest Result
  doctest Result.Enum
  doctest Result.Pipe, import: true
end
