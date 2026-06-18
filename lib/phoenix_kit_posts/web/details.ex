defmodule PhoenixKitPosts.Web.Details do
  @moduledoc """
  LiveView for displaying a single post with all details and interactions.

  Displays:
  - Post content (title, subtitle, content, media)
  - Author information
  - Post statistics (views, likes, comments)
  - Tags and groups
  - Comments via standalone CommentsComponent
  - Like/unlike functionality
  - Admin actions (edit, delete, status changes)

  ## Route

  This LiveView is mounted at `{prefix}/admin/posts/:id` and requires
  appropriate permissions.

  Note: `{prefix}` is your configured PhoenixKit URL prefix (default: `/phoenix_kit`).
  """

  use PhoenixKitWeb, :live_view

  # Forwards the comment composer's {:leaf_changed, …} process message into
  # CommentsComponent.forward_leaf_event/2 via a :handle_info lifecycle hook;
  # without it "Post Comment" silently submits empty content.
  use PhoenixKitComments.Embed

  require Logger

  alias PhoenixKit.Settings
  alias PhoenixKit.Users.Roles
  alias PhoenixKit.Utils.HtmlSanitizer
  alias PhoenixKit.Utils.Routes

  @post_preloads [:user, [media: :file], :tags, :groups, :mentions]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Post")
      |> assign(:project_title, Settings.get_project_title())
      |> assign(:current_user, socket.assigns[:phoenix_kit_current_user])
      |> assign(:post, nil)
      |> assign(:rendered_content, "")
      |> assign(:liked_by_user, false)
      |> assign(:comments_enabled, PhoenixKitComments.enabled?())
      |> assign(:likes_enabled, Settings.get_boolean_setting("posts_likes_enabled", true))
      |> assign(:show_view_count, Settings.get_boolean_setting("posts_show_view_count", true))
      |> assign(:loading, true)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => post_uuid}, _uri, socket) do
    case PhoenixKitPosts.get_post(post_uuid, preload: @post_preloads) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Post not found")
         |> push_navigate(to: Routes.path("/admin/posts"))}

      post ->
        if connected?(socket), do: PhoenixKitPosts.increment_view_count(post)

        liked_by_user =
          PhoenixKitPosts.post_liked_by?(post.uuid, socket.assigns.current_user.uuid)

        {:noreply,
         socket
         |> assign(:page_title, post.title)
         |> assign(:post, post)
         |> assign(:rendered_content, render_markdown_content(post.content))
         |> assign(:liked_by_user, liked_by_user)
         |> assign(:loading, false)}
    end
  end

  @impl true
  def handle_event("like_post", _params, socket) do
    post = socket.assigns.post
    current_user = socket.assigns.current_user

    if socket.assigns.liked_by_user do
      # Unlike
      PhoenixKitPosts.unlike_post(post.uuid, current_user.uuid)

      updated_post =
        PhoenixKitPosts.get_post!(post.uuid,
          preload: @post_preloads
        )

      {:noreply,
       socket
       |> assign(:post, updated_post)
       |> assign(:liked_by_user, false)}
    else
      # Like
      PhoenixKitPosts.like_post(post.uuid, current_user.uuid)

      updated_post =
        PhoenixKitPosts.get_post!(post.uuid,
          preload: @post_preloads
        )

      {:noreply,
       socket
       |> assign(:post, updated_post)
       |> assign(:liked_by_user, true)}
    end
  end

  @impl true
  def handle_event("edit_post", _params, socket) do
    {:noreply,
     push_navigate(socket, to: Routes.path("/admin/posts/#{socket.assigns.post.uuid}/edit"))}
  end

  @impl true
  def handle_event("delete_post", _params, socket) do
    case PhoenixKitPosts.delete_post(socket.assigns.post) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post deleted successfully")
         |> push_navigate(to: Routes.path("/admin/posts"))}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to delete post")}
    end
  end

  @impl true
  def handle_event("change_status", %{"status" => status}, socket) do
    case PhoenixKitPosts.update_post(socket.assigns.post, %{status: status}) do
      {:ok, updated_post} ->
        {:noreply,
         socket
         |> assign(:post, updated_post)
         |> put_flash(:info, "Post status updated to #{status}")}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to update post status")}
    end
  end

  # Handle comment count updates from CommentsComponent
  @impl true
  def handle_info({:comments_updated, _info}, socket) do
    updated_post =
      PhoenixKitPosts.get_post!(socket.assigns.post.uuid,
        preload: @post_preloads
      )

    {:noreply, assign(socket, :post, updated_post)}
  end

  ## --- Private Helper Functions ---

  defp user_is_admin?(user) do
    Roles.user_has_role_owner?(user) or Roles.user_has_role_admin?(user)
  end

  defp can_edit_post?(user, post) do
    user.uuid == post.user_uuid or user_is_admin?(user)
  end

  defp format_post_type("post"), do: "Post"
  defp format_post_type("snippet"), do: "Snippet"
  defp format_post_type("repost"), do: "Repost"
  defp format_post_type(_), do: "Unknown"

  defp format_status("draft"), do: "Draft"
  defp format_status("public"), do: "Public"
  defp format_status("unlisted"), do: "Unlisted"
  defp format_status("scheduled"), do: "Scheduled"
  defp format_status(_), do: "Unknown"

  defp format_type_badge_class("post"), do: "badge badge-primary"
  defp format_type_badge_class("snippet"), do: "badge badge-secondary"
  defp format_type_badge_class("repost"), do: "badge badge-accent"
  defp format_type_badge_class(_), do: "badge badge-ghost"

  defp format_status_badge_class("draft"), do: "badge badge-neutral"
  defp format_status_badge_class("public"), do: "badge badge-success"
  defp format_status_badge_class("unlisted"), do: "badge badge-warning"
  defp format_status_badge_class("scheduled"), do: "badge badge-info"
  defp format_status_badge_class(_), do: "badge badge-ghost"

  defp render_markdown_content(content) when is_binary(content) and content != "" do
    case MDEx.to_html(content, mdex_options()) do
      {:ok, html} -> HtmlSanitizer.sanitize(html)
      {:error, _error} -> ""
    end
  end

  defp render_markdown_content(_), do: ""

  # Mirrors the previous Earmark configuration (phoenix_kit dropped its
  # transitive, now-retired earmark dep in 1.7.161):
  #   * GFM → strikethrough/table/autolink/tasklist extensions
  #   * smartypants → smart typography (parse: [smart: true])
  #   * escape: false → raw HTML passthrough (render: [unsafe: true]), which is
  #     then run through HtmlSanitizer to strip XSS vectors from post content.
  # Fenced code blocks still render as `<code class="language-...">` by default,
  # matching the old `code_class_prefix: "language-"`.
  defp mdex_options do
    [
      extension: [strikethrough: true, table: true, autolink: true, tasklist: true],
      parse: [smart: true],
      render: [unsafe: true]
    ]
  end
end
