defmodule OkThen.MixProject do
  use Mix.Project

  def project do
    [
      app: :ok_then,
      version: "0.1.1",
      description: description(),
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  defp description() do
    "The Swiss Army Knife for tagged tuple pipelines"
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps() do
    [
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp docs() do
    [
      groups_for_functions: [
        Guards: &(&1[:section] == :guards),
        "Functions (:ok)": &(&1[:section] == :ok_functions),
        "Functions (:error)": &(&1[:section] == :error_functions),
        "Functions (:none)": &(&1[:section] == :none_functions),
        "Functions (any tag)": &(&1[:section] == :generic_functions)
      ],
      extras: [
        "README.md"
      ],
      main: "readme"
    ]
  end

  defp package() do
    [
      licenses: ["ISC"],
      links: %{
        "GitHub" => "https://github.com/flexibility-org/ok_then",
        "Changelog" => "https://github.com/flexibility-org/ok_then/blob/main/CHANGELOG.md",
        "Elixir Forum" => "https://elixirforum.com/t/39983"
      }
    ]
  end
end
