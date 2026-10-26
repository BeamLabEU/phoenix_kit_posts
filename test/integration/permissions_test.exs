defmodule PhoenixKitPosts.Integration.PermissionsTest do
  @moduledoc """
  Who may see and change a post, and the settings page's key.

  The LiveViews are driven by calling their callbacks with a socket carrying
  a real `Scope` — this suite has no endpoint — and every write is a crafted
  event the UI would not offer, so each test fails when its check is removed.
  """

  use PhoenixKitPosts.DataCase, async: false

  # No settings cache or internal PubSub listeners run here; core logs that.
  @moduletag :capture_log

  alias PhoenixKit.Settings
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Users.{Permissions, Roles}
  alias PhoenixKitPosts.{Access, PermissionBackfill}
  alias PhoenixKitPosts.Web

  setup do
    unless PhoenixKitPosts in PhoenixKit.ModuleRegistry.all_modules() do
      :ok = PhoenixKit.ModuleRegistry.register(PhoenixKitPosts)
      on_exit(fn -> PhoenixKit.ModuleRegistry.unregister(PhoenixKitPosts) end)
    end

    {:ok, _} = Settings.update_setting("posts_enabled", "true")

    author = user_fixture()
    other = user_fixture()

    {:ok, author: author, other: other}
  end

  defp scope_for(user, permissions) do
    %Scope{
      user: user,
      authenticated?: true,
      cached_roles: MapSet.new(),
      cached_permissions: MapSet.new(permissions)
    }
  end

  defp socket(scope, extra \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            phoenix_kit_current_scope: scope,
            phoenix_kit_current_user: scope.user,
            current_user: scope.user
          },
          extra
        )
    }
  end

  # What Web.Posts holds after mount + handle_params, so a successful event
  # can reload the list.
  defp list_socket(scope) do
    socket(scope, %{
      page: 1,
      per_page: 20,
      filter_type: "all",
      filter_status: "all",
      filter_group: "all",
      filter_tag: "all",
      search_query: "",
      bulk_uuids: [],
      posts: [],
      total_count: 0,
      stats: %{},
      loading: false
    })
  end

  defp error_flash(%Phoenix.LiveView.Socket{assigns: %{flash: flash}}), do: flash["error"]

  defp exists?(post), do: PhoenixKitPosts.get_post(post.uuid) != nil
  defp status(post), do: PhoenixKitPosts.get_post(post.uuid).status

  describe "Access" do
    test "an author manages their own post; others need posts.manage_all", ctx do
      post = post_fixture(ctx.author)

      assert Access.can_manage_post?(scope_for(ctx.author, ["posts"]), post)
      refute Access.can_manage_post?(scope_for(ctx.other, ["posts"]), post)
      assert Access.can_manage_post?(scope_for(ctx.other, ["posts", "posts.manage_all"]), post)
    end

    test "another user's draft needs posts.view_all; a published post does not", ctx do
      draft = post_fixture(ctx.author)
      public = post_fixture(ctx.author, status: "public")
      plain = scope_for(ctx.other, ["posts"])

      refute Access.can_view_post?(plain, draft)
      assert Access.can_view_post?(plain, public)
      assert Access.can_view_post?(scope_for(ctx.other, ["posts", "posts.view_all"]), draft)
    end

    test "an author's email shows only to the author or a posts.view_all holder", ctx do
      post = post_fixture(ctx.author, status: "public")

      assert Access.can_see_author_email?(scope_for(ctx.author, ["posts"]), post)
      refute Access.can_see_author_email?(scope_for(ctx.other, ["posts"]), post)

      refute Access.can_see_author_email?(
               scope_for(ctx.other, ["posts", "posts.manage_all"]),
               post
             )

      assert Access.can_see_author_email?(scope_for(ctx.other, ["posts", "posts.view_all"]), post)
    end
  end

  describe "list visibility" do
    test "without posts.view_all the list holds own posts and others' published ones", ctx do
      mine = post_fixture(ctx.other)
      their_draft = post_fixture(ctx.author)
      their_public = post_fixture(ctx.author, status: "public")

      opts = Access.list_opts(scope_for(ctx.other, ["posts"]))
      uuids = PhoenixKitPosts.list_posts(opts) |> Enum.map(& &1.uuid)

      assert mine.uuid in uuids
      assert their_public.uuid in uuids
      refute their_draft.uuid in uuids
      assert PhoenixKitPosts.count_posts(opts) == 2

      all = Access.list_opts(scope_for(ctx.other, ["posts", "posts.view_all"]))
      assert their_draft.uuid in Enum.map(PhoenixKitPosts.list_posts(all), & &1.uuid)
    end

    test "the rendered list hides others' drafts and their author's email", ctx do
      draft = post_fixture(ctx.author, title: "Hidden draft")
      _public = post_fixture(ctx.author, title: "Visible public", status: "public")

      {:noreply, socket} =
        Web.Posts.handle_params(%{}, "/admin/posts", list_socket(scope_for(ctx.other, ["posts"])))

      titles = Enum.map(socket.assigns.posts, & &1.title)
      assert "Visible public" in titles
      refute draft.title in titles
      assert socket.assigns.stats.drafts == 0
    end
  end

  describe "Web.Posts write events" do
    test "delete_post, publish_post and draft_post refuse another user's post", ctx do
      draft = post_fixture(ctx.author)
      public = post_fixture(ctx.author, status: "public")
      socket = list_socket(scope_for(ctx.other, ["posts"]))

      {:noreply, s} = Web.Posts.handle_event("delete_post", %{"id" => draft.uuid}, socket)
      assert error_flash(s) =~ "permission"
      assert exists?(draft)

      {:noreply, s} = Web.Posts.handle_event("publish_post", %{"id" => draft.uuid}, socket)
      assert error_flash(s) =~ "permission"
      assert status(draft) == "draft"

      {:noreply, s} = Web.Posts.handle_event("draft_post", %{"id" => public.uuid}, socket)
      assert error_flash(s) =~ "permission"
      assert status(public) == "public"
    end

    test "bulk_publish and bulk_delete skip posts the user may not change", ctx do
      theirs = post_fixture(ctx.author)
      mine = post_fixture(ctx.other)
      socket = list_socket(scope_for(ctx.other, ["posts"]))

      {:noreply, _} =
        Web.Posts.handle_event("bulk_publish", %{"uuids" => [theirs.uuid, mine.uuid]}, socket)

      assert status(theirs) == "draft"
      assert status(mine) == "public"

      {:noreply, _} =
        Web.Posts.handle_event("bulk_delete", %{"uuids" => [theirs.uuid, mine.uuid]}, socket)

      assert exists?(theirs)
      refute exists?(mine)
    end

    test "bulk_add_to_group adds only posts the user may change", ctx do
      theirs = post_fixture(ctx.author)
      mine = post_fixture(ctx.other)
      {:ok, group} = PhoenixKitPosts.create_group(ctx.other.uuid, %{name: "Board"})

      socket =
        ctx.other
        |> scope_for(["posts"])
        |> list_socket()
        |> Phoenix.Component.assign(:bulk_uuids, [theirs.uuid, mine.uuid])

      {:noreply, _} =
        Web.Posts.handle_event("bulk_add_to_group", %{"group_uuid" => group.uuid}, socket)

      in_group = PhoenixKitPosts.list_posts_by_group(group.uuid) |> Enum.map(& &1.uuid)
      assert mine.uuid in in_group
      refute theirs.uuid in in_group
    end

    test "posts.manage_all may change another user's post", ctx do
      draft = post_fixture(ctx.author)
      gone = post_fixture(ctx.author)
      socket = list_socket(scope_for(ctx.other, ["posts", "posts.manage_all"]))

      {:noreply, _} = Web.Posts.handle_event("publish_post", %{"id" => draft.uuid}, socket)
      assert status(draft) == "public"

      {:noreply, _} = Web.Posts.handle_event("delete_post", %{"id" => gone.uuid}, socket)
      refute exists?(gone)
    end
  end

  describe "Web.Details" do
    test "another user's draft is refused at handle_params without posts.view_all", ctx do
      draft = post_fixture(ctx.author)

      {:noreply, s} =
        Web.Details.handle_params(
          %{"id" => draft.uuid},
          "/admin/posts/#{draft.uuid}",
          socket(scope_for(ctx.other, ["posts"]), %{post: nil})
        )

      assert error_flash(s) =~ "permission"
      assert s.redirected
      assert s.assigns.post == nil
    end

    test "delete_post and change_status refuse another user's post", ctx do
      post =
        post_fixture(ctx.author, status: "public") |> Repo.preload(:user)

      socket = socket(scope_for(ctx.other, ["posts"]), %{post: post})

      {:noreply, s} = Web.Details.handle_event("delete_post", %{}, socket)
      assert error_flash(s) =~ "permission"
      assert exists?(post)

      {:noreply, s} = Web.Details.handle_event("change_status", %{"status" => "draft"}, socket)
      assert error_flash(s) =~ "permission"
      assert status(post) == "public"
    end

    test "posts.manage_all may change another user's post there", ctx do
      post = post_fixture(ctx.author, status: "public")
      socket = socket(scope_for(ctx.other, ["posts", "posts.manage_all"]), %{post: post})

      {:noreply, _} = Web.Details.handle_event("change_status", %{"status" => "draft"}, socket)
      assert status(post) == "draft"
    end
  end

  describe "Web.Edit" do
    test "opening another user's post for editing needs posts.manage_all", ctx do
      post = post_fixture(ctx.author)
      uri = "/admin/posts/#{post.uuid}/edit"

      {:noreply, refused} =
        Web.Edit.handle_params(%{"id" => post.uuid}, uri, socket(scope_for(ctx.other, ["posts"])))

      assert refused.redirected
      refute Map.get(refused.assigns, :post)
    end
  end

  describe "Web.Settings" do
    test "mount and both write events need posts.settings", ctx do
      plain = socket(scope_for(ctx.other, ["posts"]))

      {:ok, mounted} = Web.Settings.mount(%{}, %{}, plain)
      assert mounted.redirected

      {:noreply, s} =
        Web.Settings.handle_event(
          "save",
          %{"settings" => %{"posts_per_page" => "77"}},
          plain
        )

      assert error_flash(s) =~ "permission"
      refute Settings.get_setting("posts_per_page") == "77"

      {:noreply, s} = Web.Settings.handle_event("reset_defaults", %{}, plain)
      assert error_flash(s) =~ "permission"
    end

    test "a posts.settings holder saves only the page's own keys", ctx do
      {:ok, socket} =
        Web.Settings.mount(%{}, %{}, socket(scope_for(ctx.other, ["posts", "posts.settings"])))

      refute socket.redirected

      {:noreply, _} =
        Web.Settings.handle_event(
          "save",
          %{"settings" => %{"posts_per_page" => "77", "project_title" => "Hijacked"}},
          socket
        )

      assert Settings.get_setting("posts_per_page") == "77"
      refute Settings.get_setting("project_title") == "Hijacked"
    end
  end

  describe "migrate_legacy/0 backfill" do
    defp role_with(keys) do
      {:ok, role} =
        Roles.create_role(%{name: "Role-#{System.unique_integer([:positive])}", description: "t"})

      for key <- keys, do: {:ok, _} = Permissions.grant_permission(role.uuid, key, nil)
      role
    end

    defp keys(role), do: Permissions.get_permissions_for_role(role.uuid)

    test "grants every new key once to roles holding posts, and sets each flag" do
      holder = role_with(["posts"])
      outsider = role_with([])

      assert :ok = PhoenixKitPosts.migrate_legacy()

      for key <- ~w(posts.manage_all posts.view_all posts.settings) do
        assert key in keys(holder)
        refute key in keys(outsider)
      end

      for flag <-
            ~w(posts_manage_all_backfilled posts_view_all_backfilled posts_settings_backfilled) do
        assert Settings.get_setting(flag) == "true"
      end

      # A role given the base key after the backfill gets the narrow meaning.
      late = role_with(["posts"])
      assert :ok = PhoenixKitPosts.migrate_legacy()
      assert keys(late) == ["posts"]
    end

    test "a failed grant leaves the flag unset, so the next boot retries" do
      holder = role_with(["posts"])
      failing = fn _role, _key, _by -> {:error, :boom} end

      assert {:error, _} =
               PermissionBackfill.run(
                 "posts",
                 "posts.manage_all",
                 "posts_manage_all_backfilled",
                 failing
               )

      refute Settings.get_setting("posts_manage_all_backfilled") == "true"
      refute "posts.manage_all" in keys(holder)

      assert :ok =
               PermissionBackfill.run("posts", "posts.manage_all", "posts_manage_all_backfilled")

      assert "posts.manage_all" in keys(holder)
    end
  end
end
