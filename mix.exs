defmodule OkThen.MixProject do
  use Mix.Project

  def project do
    [
      app: :ok_then,
      version: "0.1.0",
      description: description(),
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        groups_for_functions: [
          Guards: &(&1[:section] == :guards)
        ]
      ],
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
  defp deps do
    [
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      licenses: ["ISC"],
      links: %{
        "GitHub" => "https://github.com/flexibility-org/ok_then"
      }
    ]
  end
end
