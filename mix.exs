defmodule SmokeTest.Mixfile do
  use Mix.Project

  def project do
    [
      app: :smoke_test,
      version: "0.1.2",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      name: "SmokeTest",
      description: description(),
      package: package(),
      deps: deps(),
      source_url: "https://github.com/matthewoden/SmokeTest"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [ 
      {:plug, "~> 1.1"},
      {:poison, "~> 3.0", optional: true},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false}
    ]
  end

  defp description do
    """ 
    A configurable Plug middleware to quickly find errors that might prevent a deployment. It can also be used as an application health-check.
    """
  end


  defp package do
    [
      maintainers: ["Matthew Potter"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/matthewoden/SmokeTest"}
    ]
  end
end
