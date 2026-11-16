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
  # Rebind gettext macros to the posts module's own catalogs (priv/gettext).
  # Must stay directly under the `use PhoenixKitWeb` line: the backend is
  # resolved at each call site's expansion, so a gettext/1 written above
  # this line would still bind to core's backend.
  use Gettext, backend: PhoenixKitPosts.Gettext

  # Forwards the comment composer's {:leaf_changed, …} process message into
  # CommentsComponent.forward_leaf_event/2 via a :handle_info lifecycle hook;
  # without it "Post Comment" silently submits empty content.
  use PhoenixKitComments.Embed

  require Logger

  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.HtmlSanitizer
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitPosts.Access
  alias PhoenixKitWeb.Actor

  @post_preloads [:user, [media: :file], :tags, :groups, :mentions]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      # Trail: Admin Panel / Posts / <post title>; the title lands in handle_params.
      |> assign(:page_title, gettext("Post"))
      |> assign(:page_section, gettext("Posts"))
      |> assign(:page_section_path, Routes.path("/admin/posts"))
      |> assign(:page_crumbs, [])
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
    post = PhoenixKitPosts.get_post(post_uuid, preload: @post_preloads)

    cond do
      is_nil(post) ->
        {:noreply,
         socket
         |> put_flash(:error, "Post not found")
         |> push_navigate(to: Routes.path("/admin/posts"))}

      # Someone else's draft or unpublished post needs `posts.view_all`
      # (or `posts.manage_all`), even when the uuid is typed in by hand.
      not Access.can_view_post?(socket.assigns[:phoenix_kit_current_scope], post) ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You don't have permission to see this post"))
         |> push_navigate(to: Routes.path("/admin/posts"))}

      true ->
        if connected?(socket), do: PhoenixKitPosts.increment_view_count(post)

        liked_by_user =
          PhoenixKitPosts.post_liked_by?(post.uuid, socket.assigns.current_user.uuid)

        {:noreply,
         socket
         |> assign(:page_title, post.title)
         |> assign(:post, post)
         |> assign(
           :rendered_content,
           __render_content__(post.content, socket.assigns[:phoenix_kit_current_scope])
         )
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
    with :ok <- authorize_change(socket) do
      do_delete_post(socket)
    end
  end

  @impl true
  def handle_event("change_status", %{"status" => status}, socket) do
    with :ok <- authorize_change(socket) do
      do_change_status(socket, status)
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

  # Delete and status changes are for the author or a `posts.manage_all`
  # holder; the buttons are hidden for everyone else, and a crafted event
  # is refused here.
  defp authorize_change(socket) do
    post = socket.assigns.post

    if post && Access.can_manage_post?(socket.assigns[:phoenix_kit_current_scope], post) do
      :ok
    else
      {:noreply,
       put_flash(socket, :error, gettext("You don't have permission to change this post"))}
    end
  end

  defp do_delete_post(socket) do
    case PhoenixKitPosts.delete_post(socket.assigns.post, Actor.opts(socket)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post deleted successfully")
         |> push_navigate(to: Routes.path("/admin/posts"))}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to delete post")}
    end
  end

  defp do_change_status(socket, status) do
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

  ## --- Private Helper Functions ---

  # The author as this viewer may see them: the email for their own post or
  # with `posts.view_all`, else the author's username.
  defp author_label(scope, post) do
    cond do
      is_nil(post.user) -> "Unknown"
      Access.can_see_author_email?(scope, post) -> post.user.email
      true -> Map.get(post.user, :username) || gettext("Another user")
    end
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

  # `[[Target]]` / `[[Target|Alias]]` (what the editor's Leaf writes) parse as
  # MDEx wiki links. Each is pointed at the post it names, resolved the way the
  # editor resolves it; one that names no post the viewer may see becomes its
  # plain text rather than a link to nowhere — or a hint that a draft exists.
  # Rewritten in the AST, so `[[…]]` inside code is never touched.
  #
  # Public (double-underscore, undocumented) only so the rendering can be
  # tested without mounting the page.
  @doc false
  def __render_content__(content, scope) when is_binary(content) and content != "" do
    with {:ok, document} <- MDEx.parse_document(content, mdex_options()),
         {:ok, html} <- MDEx.to_html(resolve_wiki_links(document, scope), mdex_options()) do
      HtmlSanitizer.sanitize(html)
    else
      {:error, _error} -> ""
    end
  end

  def __render_content__(_content, _scope), do: ""

  defp resolve_wiki_links(document, scope) do
    {_document, targets} =
      MDEx.traverse_and_update(document, [], fn
        %MDEx.WikiLink{url: url} = node, acc -> {node, [url | acc]}
        node, acc -> {node, acc}
      end)

    case targets do
      [] ->
        document

      targets ->
        resolved = PhoenixKitPosts.resolve_wiki_targets(targets, Access.list_opts(scope))

        MDEx.traverse_and_update(document, fn
          %MDEx.WikiLink{url: url} = node ->
            case Map.get(resolved, url) do
              %{uuid: uuid} -> %{node | url: Routes.path("/admin/posts/#{uuid}")}
              nil -> %MDEx.Text{literal: plain_text(node)}
            end

          node ->
            node
        end)
    end
  end

  defp plain_text(%{nodes: nodes}), do: Enum.map_join(nodes, &plain_text/1)
  defp plain_text(%{literal: literal}) when is_binary(literal), do: literal
  defp plain_text(_node), do: ""

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
      extension: [
        strikethrough: true,
        table: true,
        autolink: true,
        tasklist: true,
        wikilinks_title_after_pipe: true
      ],
      parse: [smart: true],
      render: [unsafe: true]
    ]
  end
end
