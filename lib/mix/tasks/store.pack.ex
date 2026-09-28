defmodule Mix.Tasks.Store.Pack do
  @shortdoc "Packs, signs and lists one app"

  @moduledoc """
  Builds app `<id>` into a signed pack and lists it in `manifest.json`.

      BADGE_STORE_KEY=~/.config/avm_badge/store_key mix store.pack fractals

  Compiles every app, runs `mix atomvm.check`, packs the `Badge.App.<Id>.*`
  modules into `packs/<id>-<version>.avm`, signs it and writes its entry.
  Commit and push `packs/` and `manifest.json` to publish.
  """

  use Mix.Task

  alias AvmBadgeApps.Pack

  @impl Mix.Task
  def run([id]) do
    Mix.Task.run("compile")
    # atomvm.check also lists avm_badge's host-only deps, which have no badge build; an empty ebin stands in.
    for path <- Mix.Tasks.Atomvm.Packbeam.runtime_deps(Mix.Dep.cached()), do: File.mkdir_p!(path)
    Mix.Task.run("atomvm.check")

    ebin = Mix.Project.compile_path()
    Pack.strays!(ebin)
    meta = Pack.read_meta!(id)
    key = File.read!(Path.expand(System.fetch_env!("BADGE_STORE_KEY")))

    out = Path.join("packs", "#{id}-#{meta.version}.avm")
    File.mkdir_p!("packs")
    :ok = ExAtomVM.PackBEAM.make_avm(for(beam <- Pack.beams!(ebin, id), do: {beam, :beam}), out <> ".tmp")
    pack = File.read!(out <> ".tmp")
    File.rm!(out <> ".tmp")

    byte_size(pack) <= Badge.Store.max_pack() || Mix.raise("#{out} is #{byte_size(pack)} bytes, over #{Badge.Store.max_pack()}")
    Pack.check_immutable!(out, pack)
    File.write!(out, pack)

    entry = Pack.entry(id, meta, pack, Badge.Store.api(), key)
    File.write!("manifest.json", Pack.encode_manifest(Pack.upsert(Pack.read_manifest("manifest.json"), entry)))

    Mix.shell().info("#{out}: #{byte_size(pack)} bytes, api #{entry["api"]}, sha256 #{entry["sha256"]}")
  end

  def run(_args), do: Mix.raise("usage: mix store.pack <id>")
end
