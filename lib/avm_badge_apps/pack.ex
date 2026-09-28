defmodule AvmBadgeApps.Pack do
  @moduledoc "The pure half of `mix store.pack`: metadata, module selection, signing and the manifest."

  @fields [:name, :author, :description, :version, :storage]
  @allowed ["Elixir.Badge.App.", "Elixir.AvmBadgeApps.", "Elixir.Mix.Tasks.Store."]

  @doc "The checked store metadata in `apps/<id>/app.exs`."
  def read_meta!(id) do
    {meta, _binding} = Code.eval_file(Path.join(["apps", id, "app.exs"]))
    validate_meta!(id, Map.new(meta))
  end

  @doc "`meta` if it fits the manifest's limits; raises `Mix.Error` otherwise."
  def validate_meta!(id, meta) do
    Badge.Store.valid_id?(id) || Mix.raise("app id #{inspect(id)} must be a lowercase letter and up to 14 lowercase letters or digits")

    for field <- @fields, not is_binary(Map.get(meta, field)) do
      Mix.raise("apps/#{id}/app.exs: #{field} must be a string")
    end

    byte_size(meta.name) <= 13 || Mix.raise("apps/#{id}/app.exs: name is over 13 bytes, the width of a home grid cell")
    byte_size(meta.author) <= 32 || Mix.raise("apps/#{id}/app.exs: author is over 32 bytes")
    byte_size(meta.description) <= 120 || Mix.raise("apps/#{id}/app.exs: description is over 120 bytes")
    byte_size(meta.version) <= 16 || Mix.raise("apps/#{id}/app.exs: version is over 16 bytes")
    meta.storage in ["ram", "flash"] || Mix.raise("apps/#{id}/app.exs: storage must be \"ram\" or \"flash\"")
    meta
  end

  @doc "The beam file prefix every module of app `id` carries."
  def prefix(id), do: "Elixir.Badge.App.#{Macro.camelize(id)}."

  @doc "App `id`'s beams in `ebin`, sorted; raises when its page module is missing."
  def beams!(ebin, id) do
    prefix = prefix(id)
    beams = for file <- File.ls!(ebin), String.starts_with?(file, prefix), String.ends_with?(file, ".beam"), do: file

    (prefix <> "Page.beam") in beams || Mix.raise("app #{id} has no #{String.trim_leading(prefix, "Elixir.")}Page module")

    beams |> Enum.sort() |> Enum.map(&Path.join(ebin, &1))
  end

  @doc "Raises when `ebin` holds a module outside every app's namespace."
  def strays!(ebin) do
    strays =
      for file <- File.ls!(ebin), String.ends_with?(file, ".beam"), not Enum.any?(@allowed, &String.starts_with?(file, &1)), do: file

    strays == [] || Mix.raise("modules outside Badge.App.<Id>: #{Enum.join(strays, ", ")}")
    :ok
  end

  @doc "The signed manifest entry for `pack`."
  def entry(id, meta, pack, api, key) do
    sha = Badge.Store.hex(:crypto.hash(:sha256, pack))
    signed = %{id: id, version: meta.version, api: api, storage: meta.storage}
    sig = :crypto.sign(:ecdsa, :sha256, Badge.Store.signed_message(signed, sha), [key, :secp256r1])

    %{
      "id" => id,
      "name" => meta.name,
      "author" => meta.author,
      "description" => meta.description,
      "version" => meta.version,
      "size" => byte_size(pack),
      "storage" => meta.storage,
      "api" => api,
      "sha256" => sha,
      "sig" => Base.encode64(sig)
    }
  end

  @doc "`manifest` with `entry` in place of the same id, apps ordered by id."
  def upsert(manifest, entry) do
    others = Enum.reject(Map.get(manifest, "apps", []), &(&1["id"] == entry["id"]))
    Map.put(manifest, "apps", Enum.sort_by([entry | others], & &1["id"]))
  end

  @doc "Raises when `path` is already published with other bytes than `pack`."
  def check_immutable!(path, pack) do
    case File.read(path) do
      {:ok, ^pack} -> :ok
      {:ok, _other} -> Mix.raise("#{path} is already published with different bytes; bump the version")
      {:error, :enoent} -> :ok
    end
  end

  @doc "The manifest at `path`, or an empty one."
  def read_manifest(path) do
    case File.read(path) do
      {:ok, json} -> JSON.decode!(json)
      {:error, :enoent} -> %{"apps" => []}
    end
  end

  @doc "The manifest as pretty JSON."
  def encode_manifest(manifest), do: IO.iodata_to_binary([:json.format(manifest), "\n"])
end
