defmodule PhoenixKitPosts.Integration.WikiLinksTest do
  @moduledoc """
  `[[Target]]` wiki links: how a target resolves to a post
  (`PhoenixKitPosts.resolve_wiki_targets/2`), what the editor answers Leaf and
  does on a click, and how the details page renders them.

  A link must never reveal a post its viewer may not see, so every path is
  checked against someone else's draft. The LiveViews are driven by calling
  their callbacks with a socket carrying a real `Scope` (no endpoint here).
  """

  use PhoenixKitPosts.DataCase, async: false

  @moduletag :capture_log

  alias Phoenix.LiveView.Utils, as: LiveViewUtils
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitPosts.Web

  setup do
    # `Scope.can?/2` grants nothing for a module that is not registered and
    # enabled, so `posts.view_all` would otherwise read as absent.
    unless PhoenixKitPosts in PhoenixKit.ModuleRegistry.all_modules() do
      :ok = PhoenixKit.ModuleRegistry.register(PhoenixKitPosts)
      on_exit(fn -> PhoenixKit.ModuleRegistry.unregister(PhoenixKitPosts) end)
    end

    {:ok, _} = PhoenixKit.Settings.update_setting("posts_enabled", "true")

    {:ok, author: user_fixture(), other: user_fixture()}
  end

  defp scope_for(user, permissions \\ ["posts"]) do
    %Scope{
      user: user,
      authenticated?: true,
      cached_roles: MapSet.new(),
      cached_permissions: MapSet.new(permissions)
    }
  end

  defp socket(scope) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        phoenix_kit_current_scope: scope,
        phoenix_kit_current_user: scope.user,
        current_user: scope.user
      }
    }
  end

  defp pushed_events(socket), do: LiveViewUtils.get_push_events(socket)

  describe "resolve_wiki_targets/2" do
    test "matches by slug, then by title case-insensitively, ignoring #heading", ctx do
      by_slug = post_fixture(ctx.author, title: "Slugged", slug: "the-slug", status: "public")
      by_title = post_fixture(ctx.author, title: "Release Notes", status: "public")

      slug_uuid = by_slug.uuid
      title_uuid = by_title.uuid

      assert %{
               "the-slug" => %{uuid: ^slug_uuid},
               "release notes" => %{uuid: ^title_uuid},
               " Release Notes#Intro" => %{uuid: ^title_uuid},
               "Nothing Here" => nil,
               "" => nil
             } =
               PhoenixKitPosts.resolve_wiki_targets([
                 "the-slug",
                 "release notes",
                 " Release Notes#Intro",
                 "Nothing Here",
                 ""
               ])
    end

    test "a slug match wins over another post's title", ctx do
      slugged = post_fixture(ctx.author, slug: "roadmap", title: "Plans", status: "public")
      _titled = post_fixture(ctx.author, title: "roadmap", status: "public")

      assert %{"roadmap" => %{uuid: uuid}} = PhoenixKitPosts.resolve_wiki_targets(["roadmap"])
      assert uuid == slugged.uuid
    end

    test "the oldest post wins a shared title", ctx do
      old =
        post_fixture(ctx.author,
          title: "Twin",
          status: "public",
          inserted_at: ~U[2026-01-01 00:00:00Z]
        )

      _new = post_fixture(ctx.author, title: "Twin", status: "public")

      assert %{"Twin" => %{uuid: uuid}} = PhoenixKitPosts.resolve_wiki_targets(["Twin"])
      assert uuid == old.uuid
    end

    test ":visible_to hides other people's drafts but not one's own", ctx do
      theirs = post_fixture(ctx.other, title: "Secret Draft")
      mine = post_fixture(ctx.author, title: "My Draft")

      assert %{"Secret Draft" => nil, "My Draft" => %{uuid: mine_uuid}} =
               PhoenixKitPosts.resolve_wiki_targets(["Secret Draft", "My Draft"],
                 visible_to: ctx.author.uuid
               )

      assert mine_uuid == mine.uuid

      assert %{"Secret Draft" => %{uuid: theirs_uuid}} =
               PhoenixKitPosts.resolve_wiki_targets(["Secret Draft"])

      assert theirs_uuid == theirs.uuid
    end

    test "non-binary targets are skipped and an empty list makes no query" do
      assert PhoenixKitPosts.resolve_wiki_targets([nil, 1, %{}]) == %{}
      assert PhoenixKitPosts.resolve_wiki_targets([]) == %{}
    end
  end

  describe "Web.Edit" do
    test "answers Leaf with hrefs for visible posts and missing for hidden ones", ctx do
      public = post_fixture(ctx.other, title: "Shared", status: "public")
      _draft = post_fixture(ctx.other, title: "Hidden")

      {:noreply, _} =
        Web.Edit.handle_info(
          {:leaf_resolve_links,
           %{editor_id: "post-content-editor", targets: ["Shared", "Hidden"], seq: 7}},
          socket(scope_for(ctx.author))
        )

      assert_received {:phoenix, :send_update, {{Leaf, "post-content-editor"}, update}}
      assert %{action: :link_targets, seq: 7, targets: targets} = update

      href = Routes.path("/admin/posts/#{public.uuid}")

      assert %{
               "Shared" => %{href: ^href, exists: true, title: "Shared"},
               "Hidden" => %{href: nil, exists: false, title: tooltip}
             } = targets

      assert is_binary(tooltip)
    end

    test "a click opens an existing post in a new tab, ignoring the client's href", ctx do
      post = post_fixture(ctx.author, title: "Target", status: "public")

      {:noreply, s} =
        Web.Edit.handle_info(
          {:leaf_link_clicked,
           %{target: "Target", heading: nil, href: "https://evil.example", modifier: true}},
          socket(scope_for(ctx.author))
        )

      url = Routes.path("/admin/posts/#{post.uuid}")
      assert [["phoenix-kit-posts:open-url", %{url: ^url}]] = pushed_events(s)
    end

    test "a click on a missing or hidden target opens a prefilled new post", ctx do
      _draft = post_fixture(ctx.other, title: "Their Draft")

      for target <- ["A & B = C?#Heading", "Their Draft"] do
        {:noreply, s} =
          Web.Edit.handle_info(
            {:leaf_link_clicked, %{target: target, heading: nil, href: nil, modifier: true}},
            socket(scope_for(ctx.author))
          )

        assert [["phoenix-kit-posts:open-url", %{url: url}]] = pushed_events(s)
        assert %URI{path: path, query: query} = URI.parse(url)
        assert path == Routes.path("/admin/posts/new")

        assert URI.decode_query(query) == %{
                 "title" => PhoenixKitPosts.wiki_target_name(target)
               }
      end
    end

    test "a blank target does nothing", ctx do
      {:noreply, s} =
        Web.Edit.handle_info(
          {:leaf_link_clicked, %{target: "  ", heading: nil, href: nil, modifier: true}},
          socket(scope_for(ctx.author))
        )

      assert pushed_events(s) == []
    end
  end

  describe "Web.Details" do
    test "links resolved targets, flattens the rest, leaves code alone", ctx do
      public = post_fixture(ctx.other, title: "Shared", status: "public")
      _draft = post_fixture(ctx.other, title: "Hidden")

      html =
        Web.Details.__render_content__(
          "See [[Shared|the shared post]], [[Hidden]] and [[Nope]].\n\n`[[Shared]]`",
          scope_for(ctx.author)
        )

      href = Routes.path("/admin/posts/#{public.uuid}")
      assert html =~ ~s(href="#{href}")
      assert html =~ "the shared post"
      assert html =~ "Hidden"
      assert html =~ "Nope"
      assert html =~ "<code>[[Shared]]</code>"
      refute html =~ "[[Hidden]]"
      assert length(Regex.scan(~r/<a /, html)) == 1
    end

    test "a viewer with posts.view_all gets a link to someone else's draft", ctx do
      draft = post_fixture(ctx.other, title: "Hidden")

      html =
        Web.Details.__render_content__(
          "[[Hidden]]",
          scope_for(ctx.author, ["posts", "posts.view_all"])
        )

      assert html =~ ~s(href="#{Routes.path("/admin/posts/#{draft.uuid}")}")
    end
  end
end
