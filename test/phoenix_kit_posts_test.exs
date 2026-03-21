defmodule PhoenixKitPostsTest do
  use ExUnit.Case

  describe "behaviour implementation" do
    test "implements PhoenixKit.Module" do
      behaviours =
        PhoenixKitPosts.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert PhoenixKit.Module in behaviours
    end

    test "has @phoenix_kit_module attribute for auto-discovery" do
      attrs = PhoenixKitPosts.__info__(:attributes)
      assert Keyword.get(attrs, :phoenix_kit_module) == [true]
    end
  end

  describe "required callbacks" do
    test "module_key/0 returns a non-empty string" do
      key = PhoenixKitPosts.module_key()
      assert is_binary(key)
      assert key == "posts"
    end

    test "module_name/0 returns a non-empty string" do
      name = PhoenixKitPosts.module_name()
      assert is_binary(name)
      assert name == "Posts"
    end

    test "enabled?/0 returns a boolean" do
      assert is_boolean(PhoenixKitPosts.enabled?())
    end

    test "enable_system/0 is exported" do
      assert function_exported?(PhoenixKitPosts, :enable_system, 0)
    end

    test "disable_system/0 is exported" do
      assert function_exported?(PhoenixKitPosts, :disable_system, 0)
    end
  end

  describe "permission_metadata/0" do
    test "returns a map with required fields" do
      meta = PhoenixKitPosts.permission_metadata()
      assert %{key: key, label: label, icon: icon, description: desc} = meta
      assert is_binary(key)
      assert is_binary(label)
      assert is_binary(icon)
      assert is_binary(desc)
    end

    test "key matches module_key" do
      meta = PhoenixKitPosts.permission_metadata()
      assert meta.key == PhoenixKitPosts.module_key()
    end

    test "icon uses hero- prefix" do
      meta = PhoenixKitPosts.permission_metadata()
      assert String.starts_with?(meta.icon, "hero-")
    end
  end

  describe "admin_tabs/0" do
    test "returns a list of Tab structs" do
      tabs = PhoenixKitPosts.admin_tabs()
      assert is_list(tabs)
      assert length(tabs) >= 3
    end

    test "main tab has required fields" do
      [tab | _] = PhoenixKitPosts.admin_tabs()
      assert tab.id == :admin_posts
      assert tab.label == "Posts"
      assert is_binary(tab.path)
      assert tab.level == :admin
      assert tab.permission == PhoenixKitPosts.module_key()
      assert tab.group == :admin_modules
    end

    test "main tab has live_view for route generation" do
      [tab | _] = PhoenixKitPosts.admin_tabs()
      assert {PhoenixKitPosts.Web.Posts, :index} = tab.live_view
    end

    test "tab paths use hyphens not underscores" do
      for tab <- PhoenixKitPosts.admin_tabs() do
        # Skip paths with :id parameter
        unless String.contains?(tab.path, ":") do
          refute String.contains?(tab.path, "_"),
                 "Tab path #{tab.path} contains underscores — use hyphens"
        end
      end
    end

    test "all tabs have live_view tuples" do
      for tab <- PhoenixKitPosts.admin_tabs() do
        assert {_module, _action} = tab.live_view,
               "Tab #{tab.id} is missing live_view tuple"
      end
    end
  end

  describe "settings_tabs/0" do
    test "returns a list with settings tab" do
      tabs = PhoenixKitPosts.settings_tabs()
      assert is_list(tabs)
      assert length(tabs) == 1
    end

    test "settings tab has live_view for route generation" do
      [tab] = PhoenixKitPosts.settings_tabs()
      assert {PhoenixKitPosts.Web.Settings, :index} = tab.live_view
    end
  end

  describe "version/0" do
    test "returns a version string" do
      version = PhoenixKitPosts.version()
      assert is_binary(version)
      assert version == "0.1.0"
    end
  end

  describe "optional callbacks have defaults" do
    test "get_config/0 returns a map" do
      config = PhoenixKitPosts.get_config()
      assert is_map(config)
      assert Map.has_key?(config, :enabled)
    end
  end
end
