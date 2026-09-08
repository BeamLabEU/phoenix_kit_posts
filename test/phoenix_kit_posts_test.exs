defmodule PhoenixKitPostsTest do
  use ExUnit.Case

  # `function_exported?/3` answers FALSE for a module that is merely not
  # loaded, not only for one that lacks the function, so a bare callback
  # assertion fails intermittently under a random seed and never when the file
  # runs alone -- the shape that reads as flaky infrastructure and gets re-run
  # instead of fixed. Reproduced in two sibling modules before this went in.
  setup_all do
    Code.ensure_loaded!(PhoenixKitPosts)
    :ok
  end

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
    test "returns a version string matching mix.exs" do
      version = PhoenixKitPosts.version()
      assert is_binary(version)
      assert version == Mix.Project.config()[:version]
    end
  end

  describe "hex package" do
    test "ships priv/ so the module's gettext catalogs are in the published tarball" do
      files = Mix.Project.config()[:package][:files]

      assert "priv" in files,
             "priv/ must be listed in package files, otherwise priv/gettext/**/*.po " <>
               "is excluded from the Hex tarball and every non-English translation " <>
               "silently falls back to the English msgid"
    end
  end

  describe "gettext backend" do
    test "resolves the module's own translations instead of falling back to the msgid" do
      # Guards the whole point of the module's Gettext backend: the admin
      # LiveViews rebind gettext to PhoenixKitPosts.Gettext, so its catalogs
      # must compile in and resolve. "ru" comes from priv/gettext/ru.
      Gettext.put_locale(PhoenixKitPosts.Gettext, "ru")
      assert Gettext.gettext(PhoenixKitPosts.Gettext, "Content Limits") == "Лимиты контента"
    end

    test "every LiveView that calls gettext rebinds the backend first" do
      # The defect this guards: `use PhoenixKitWeb, :live_view` binds the
      # gettext macros to CORE's backend, and the rebinding `use Gettext,
      # backend:` line has to come BEFORE the call sites (the backend is
      # resolved per call site at expansion time). Get it wrong and the
      # msgid lands in core's catalogue instead of this package's — no
      # compile error, no runtime signal, just raw English in et/ru.
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          String.contains?(File.read!(path), "gettext(") do
        # A colocated template compiles into its module, so the rebinding
        # lives in the .ex next to it.
        module_path = String.replace_suffix(path, ".html.heex", ".ex")

        assert File.exists?(module_path),
               "#{path} calls gettext/1 but has no companion module to carry the rebinding"

        assert File.read!(module_path) =~ ~r/use Gettext, backend: PhoenixKitPosts\.Gettext/,
               "#{module_path} calls gettext/1 (in itself or in #{path}) but never rebinds " <>
                 "the backend to PhoenixKitPosts.Gettext"
      end
    end

    test "every extracted msgid is in the catalogues" do
      # A code-vs-catalogue diff, which is the only honest completeness check:
      # a msgid bound to the wrong backend is missing here while every
      # empty-msgstr count still reads "complete".
      pot = File.read!("priv/gettext/default.pot")

      known =
        ~r/^msgid "(.*)"$/m
        |> Regex.scan(pot)
        |> MapSet.new(fn [_, msgid] -> msgid end)

      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          [_, msgid] <- Regex.scan(~r/\bgettext\("((?:[^"\\]|\\.)*)"/, File.read!(path)) do
        assert MapSet.member?(known, msgid),
               "#{path} uses gettext(#{inspect(msgid)}) but it is not in " <>
                 "priv/gettext/default.pot — run `mix gettext.extract && " <>
                 "mix gettext.merge priv/gettext`"
      end
    end
  end

  describe "js_sources/0" do
    # The hook this declares replaced an inline <script>, which morphdom never
    # executes after a LiveView navigation. The replacement fails just as
    # silently if the bundle is not where the declaration says it is: core's
    # :phoenix_kit_js_sources compiler resolves it through :code.priv_dir/1.
    test "declares a bundle that exists in this app's priv/" do
      for %{app: app, file: file, global: global} <- PhoenixKitPosts.js_sources() do
        assert app == :phoenix_kit_posts

        path = Path.join(to_string(:code.priv_dir(app)), file)
        assert File.exists?(path), "js_sources/0 declares #{file}, which is not in priv/"

        # The fold into window.PhoenixKitHooks is last-write-wins across every
        # module's bundle and core's own hooks, so the global — and the hook
        # names inside it — must be namespaced.
        assert global =~ ~r/^PhoenixKitPosts/
        assert File.read!(path) =~ "window.#{global}"
      end
    end

    test "the template's phx-hook names a hook the bundle defines" do
      bundle =
        :phoenix_kit_posts
        |> :code.priv_dir()
        |> to_string()
        |> Path.join("static/assets/phoenix_kit_posts.js")
        |> File.read!()

      for path <- Path.wildcard("lib/**/*.heex"),
          [_, hook] <- Regex.scan(~r/phx-hook="(PhoenixKitPosts[^"]+)"/, File.read!(path)) do
        assert bundle =~ "PhoenixKitPostsHooks.#{hook}",
               "#{path} mounts phx-hook=#{inspect(hook)}, which the bundle does not define"
      end
    end
  end

  describe "editor mode" do
    # The post editor passes this value straight to Leaf's :mode attr, whose
    # internal normalize_mode/2 has no catch-all clause — an unknown mode
    # crashes the editor rather than degrading. Core's get_editor_mode/0 is
    # also absent from older pinned builds, so every path must land on a
    # mode Leaf accepts.
    alias PhoenixKitPosts.Web.Edit

    test "passes through the modes Leaf accepts" do
      for mode <- [:visual, :hybrid, :markdown, :html] do
        assert Edit.__normalize_editor_mode__(mode) == mode
      end
    end

    test "converts the setting's string values to atoms" do
      assert Edit.__normalize_editor_mode__("visual") == :visual
      assert Edit.__normalize_editor_mode__("markdown") == :markdown
      assert Edit.__normalize_editor_mode__("html") == :html
      assert Edit.__normalize_editor_mode__("hybrid") == :hybrid
    end

    test "falls back to :hybrid for unknown or missing values" do
      assert Edit.__normalize_editor_mode__("wysiwyg") == :hybrid
      assert Edit.__normalize_editor_mode__(:wysiwyg) == :hybrid
      assert Edit.__normalize_editor_mode__(nil) == :hybrid
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
