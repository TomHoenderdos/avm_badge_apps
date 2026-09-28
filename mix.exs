# Apps run on the badge, so everything here builds for its target.
Mix.target(:badge)

defmodule AvmBadgeApps.MixProject do
  use Mix.Project

  def project do
    [
      app: :avm_badge_apps,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib" | Path.wildcard("apps/*/lib")],
      deps: [{:avm_badge, path: "../avm_badge"}]
    ]
  end

  def application, do: [extra_applications: [:crypto]]
end
