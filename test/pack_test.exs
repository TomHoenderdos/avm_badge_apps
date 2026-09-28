defmodule AvmBadgeApps.PackTest do
  use ExUnit.Case, async: true

  alias AvmBadgeApps.Pack

  @meta %{name: "Demo", author: "Ann", description: "A demo", version: "1.0.0", storage: "ram", category: "games"}

  test "metadata must fit the manifest limits" do
    assert Pack.validate_meta!("demo", @meta) == @meta
    assert_raise Mix.Error, fn -> Pack.validate_meta!("Demo", @meta) end
    assert_raise Mix.Error, fn -> Pack.validate_meta!("demo", %{@meta | name: String.duplicate("n", 14)}) end
    assert_raise Mix.Error, fn -> Pack.validate_meta!("demo", %{@meta | storage: "disk"}) end
    assert_raise Mix.Error, ~r/category/, fn -> Pack.validate_meta!("demo", %{@meta | category: "fun"}) end
    assert_raise Mix.Error, ~r/category/, fn -> Pack.validate_meta!("demo", Map.delete(@meta, :category)) end
    assert_raise Mix.Error, fn -> Pack.validate_meta!("demo", Map.delete(@meta, :author)) end
  end

  test "an app packs its own namespace and needs a page" do
    dir = Path.join(System.tmp_dir!(), "pack_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    for name <- ~w(Elixir.Badge.App.Demo.Page Elixir.Badge.App.Demo.Maths Elixir.Badge.App.Other.Page Elixir.AvmBadgeApps.Pack) do
      File.write!(Path.join(dir, name <> ".beam"), "")
    end

    assert Pack.prefix("demo") == "Elixir.Badge.App.Demo."
    assert Enum.map(Pack.beams!(dir, "demo"), &Path.basename/1) == ["Elixir.Badge.App.Demo.Maths.beam", "Elixir.Badge.App.Demo.Page.beam"]
    assert_raise Mix.Error, fn -> Pack.beams!(dir, "none") end
    assert Pack.strays!(dir) == :ok

    File.write!(Path.join(dir, "Elixir.Badge.Fractal.beam"), "")
    assert_raise Mix.Error, ~r/Badge.Fractal/, fn -> Pack.strays!(dir) end
  end

  test "an entry signed here verifies on the badge" do
    {pub, priv} = :crypto.generate_key(:ecdh, :secp256r1)
    pack = :crypto.strong_rand_bytes(300)
    entry = Pack.entry("demo", @meta, pack, Badge.Store.api(), priv)

    {:ok, [decoded]} = Badge.Store.decode_manifest(Pack.encode_manifest(%{"apps" => [entry]}))
    assert decoded.category == "games"
    assert Badge.Store.verify(decoded, pack, pub) == :ok
  end

  test "upsert replaces the same id and keeps apps ordered by id" do
    manifest = %{"apps" => [%{"id" => "b", "version" => "1"}]}
    manifest = Pack.upsert(manifest, %{"id" => "a", "version" => "1"})
    manifest = Pack.upsert(manifest, %{"id" => "b", "version" => "2"})

    assert manifest["apps"] == [%{"id" => "a", "version" => "1"}, %{"id" => "b", "version" => "2"}]
  end

  test "a published pack cannot change its bytes" do
    path = Path.join(System.tmp_dir!(), "pack_immutable_#{System.unique_integer([:positive])}.avm")
    assert Pack.check_immutable!(path, "one") == :ok
    File.write!(path, "one")
    assert Pack.check_immutable!(path, "one") == :ok
    assert_raise Mix.Error, fn -> Pack.check_immutable!(path, "two") end
  end
end
