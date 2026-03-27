defmodule PhoenixKitPosts do
  @moduledoc """
  Context for managing posts, likes, tags, and groups.

  Provides complete API for the social posts system including CRUD operations,
  counter cache management, tag assignment, and group organization.
  Comments are now handled by the standalone `PhoenixKit.Modules.Comments` module.

  ## Features

  - **Post Management**: Create, update, delete, publish, schedule posts
  - **Like System**: Like/unlike posts, check like status
  - **Comment System**: Nested threaded comments with unlimited depth
  - **Tag System**: Hashtag categorization with auto-slugification
  - **Group System**: User collections for organizing posts
  - **Media Attachments**: Multiple images per post with ordering
  - **Publishing**: Draft/public/unlisted/scheduled status management
  - **Analytics**: View tracking (future feature)

  ## Examples

      # Create a post
      {:ok, post} = PhoenixKitPosts.create_post(user_uuid, %{
        title: "My First Post",
        content: "Hello world!",
        type: "post",
        status: "draft"
      })

      # Publish a post
      {:ok, post} = PhoenixKitPosts.publish_post(post)

      # Like a post
      {:ok, like} = PhoenixKitPosts.like_post(post.uuid, user_uuid)

      # Add a comment
      {:ok, comment} = PhoenixKitPosts.create_comment(post.uuid, user_uuid, %{
        content: "Great post!"
      })

      # Create a group
      {:ok, group} = PhoenixKitPosts.create_group(user_uuid, %{
        name: "Travel Photos",
        description: "My adventures"
      })
  """

  use PhoenixKit.Module

  import Ecto.Query, warn: false
  require Logger

  alias PhoenixKit.Dashboard.Tab

  alias PhoenixKitPosts.{
    Post,
    PostDislike,
    PostGroup,
    PostGroupAssignment,
    PostLike,
    PostMedia,
    PostMention,
    PostTag,
    PostTagAssignment,
    ScheduledPostHandler
  }

  alias PhoenixKit.ScheduledJobs
  alias PhoenixKit.Settings
  alias PhoenixKit.Users.Auth
  alias PhoenixKit.Utils.Date, as: UtilsDate
  alias PhoenixKit.Utils.UUID, as: UUIDUtils

  # ============================================================================
  # Module Status
  # ============================================================================

  @impl PhoenixKit.Module
  @doc """
  Checks if the Posts module is enabled.

  ## Examples

      iex> enabled?()
      true
  """
  def enabled? do
    Settings.get_boolean_setting("posts_enabled", true)
  rescue
    _ -> false
  end

  @impl PhoenixKit.Module
  @doc """
  Enables the Posts module.

  ## Examples

      iex> enable_system()
      {:ok, %Setting{}}
  """
  def enable_system do
    Settings.update_boolean_setting_with_module("posts_enabled", true, "posts")
  end

  @impl PhoenixKit.Module
  @doc """
  Disables the Posts module.

  ## Examples

      iex> disable_system()
      {:ok, %Setting{}}
  """
  def disable_system do
    Settings.update_boolean_setting_with_module("posts_enabled", false, "posts")
  end

  @impl PhoenixKit.Module
  @doc """
  Gets the current Posts module configuration and stats.

  ## Examples

      iex> get_config()
      %{enabled: true, total_posts: 42, published_posts: 30, ...}
  """
  def get_config do
    %{
      enabled: enabled?(),
      total_posts: count_posts(),
      published_posts: count_posts(status: "public"),
      draft_posts: count_posts(status: "draft"),
      likes_enabled: Settings.get_boolean_setting("posts_likes_enabled", true)
    }
  end

  # ============================================================================
  # Module Behaviour Callbacks
  # ============================================================================

  @impl PhoenixKit.Module
  def module_key, do: "posts"

  @impl PhoenixKit.Module
  def module_name, do: "Posts"

  @impl PhoenixKit.Module
  def version, do: "0.1.0"

  @impl PhoenixKit.Module
  def permission_metadata do
    %{
      key: "posts",
      label: "Posts",
      icon: "hero-document-text",
      description: "Blog posts, categories, and content publishing"
    }
  end

  @impl PhoenixKit.Module
  def admin_tabs do
    [
      Tab.new!(
        id: :admin_posts,
        label: "Posts",
        icon: "hero-document-text",
        path: "posts",
        priority: 580,
        level: :admin,
        permission: "posts",
        match: :prefix,
        group: :admin_modules,
        subtab_display: :when_active,
        highlight_with_subtabs: false,
        live_view: {PhoenixKitPosts.Web.Posts, :index}
      ),
      Tab.new!(
        id: :admin_posts_all,
        label: "All Posts",
        icon: "hero-newspaper",
        path: "posts",
        priority: 581,
        level: :admin,
        permission: "posts",
        parent: :admin_posts,
        match: :exact,
        live_view: {PhoenixKitPosts.Web.Posts, :index}
      ),
      Tab.new!(
        id: :admin_posts_groups,
        label: "Groups",
        icon: "hero-folder",
        path: "posts/groups",
        priority: 582,
        level: :admin,
        permission: "posts",
        parent: :admin_posts,
        live_view: {PhoenixKitPosts.Web.Groups, :index}
      ),
      # Hidden tabs for CRUD pages
      Tab.new!(
        id: :admin_posts_new,
        label: "New Post",
        path: "posts/new",
        level: :admin,
        permission: "posts",
        parent: :admin_posts,
        visible: false,
        live_view: {PhoenixKitPosts.Web.Edit, :new}
      ),
      Tab.new!(
        id: :admin_posts_edit,
        label: "Edit Post",
        path: "posts/:id/edit",
        level: :admin,
        permission: "posts",
        parent: :admin_posts,
        visible: false,
        live_view: {PhoenixKitPosts.Web.Edit, :edit}
      ),
      Tab.new!(
        id: :admin_posts_details,
        label: "Post Details",
        path: "posts/:id",
        level: :admin,
        permission: "posts",
        parent: :admin_posts,
        visible: false,
        live_view: {PhoenixKitPosts.Web.Details, :show}
      ),
      Tab.new!(
        id: :admin_posts_group_new,
        label: "New Group",
        path: "posts/groups/new",
        level: :admin,
        permission: "posts",
        parent: :admin_posts,
        visible: false,
        live_view: {PhoenixKitPosts.Web.GroupEdit, :new}
      ),
      Tab.new!(
        id: :admin_posts_group_edit,
        label: "Edit Group",
        path: "posts/groups/:id/edit",
        level: :admin,
        permission: "posts",
        parent: :admin_posts,
        visible: false,
        live_view: {PhoenixKitPosts.Web.GroupEdit, :edit}
      )
    ]
  end

  @impl PhoenixKit.Module
  def settings_tabs do
    [
      Tab.new!(
        id: :admin_settings_posts,
        label: "Posts",
        icon: "hero-newspaper",
        path: "posts",
        priority: 922,
        level: :admin,
        parent: :admin_settings,
        permission: "posts",
        live_view: {PhoenixKitPosts.Web.Settings, :index}
      )
    ]
  end

  # ============================================================================
  # CRUD Operations
  # ============================================================================

  @doc """
  Creates a new post.

  ## Parameters

  - `user_uuid` - Owner UUID (UUIDv7 string)
  - `attrs` - Post attributes (title, content, type, status, etc.)

  ## Examples

      iex> create_post("019145a1-...", %{title: "Test", content: "Content", type: "post"})
      {:ok, %Post{}}

      iex> create_post("019145a1-...", %{title: "", content: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_post(user_uuid, attrs) when is_binary(user_uuid) do
    create_post_with_uuid(user_uuid, attrs)
  end

  defp create_post_with_uuid(user_uuid, attrs) do
    case Auth.get_user(user_uuid) do
      %{uuid: uuid} ->
        attrs =
          attrs
          |> Map.put("user_uuid", uuid)

        %Post{}
        |> Post.changeset(attrs)
        |> repo().insert()

      nil ->
        {:error, :user_not_found}
    end
  end

  @doc """
  Updates an existing post.

  ## Parameters

  - `post` - Post struct to update
  - `attrs` - Attributes to update

  ## Examples

      iex> update_post(post, %{title: "Updated Title"})
      {:ok, %Post{}}

      iex> update_post(post, %{title: ""})
      {:error, %Ecto.Changeset{}}
  """
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a post and all related data (cascades to media, likes, comments, etc.).

  ## Parameters

  - `post` - Post struct to delete

  ## Examples

      iex> delete_post(post)
      {:ok, %Post{}}

      iex> delete_post(post)
      {:error, %Ecto.Changeset{}}
  """
  def delete_post(%Post{} = post) do
    repo().delete(post)
  end

  @doc """
  Gets a single post by ID with optional preloads.

  Raises `Ecto.NoResultsError` if post not found.

  ## Parameters

  - `id` - Post ID (UUIDv7)
  - `opts` - Options
    - `:preload` - List of associations to preload

  ## Examples

      iex> get_post!("018e3c4a-...")
      %Post{}

      iex> get_post!("018e3c4a-...", preload: [:user, :media, :tags])
      %Post{user: %User{}, media: [...], tags: [...]}

      iex> get_post!("nonexistent")
      ** (Ecto.NoResultsError)
  """
  def get_post!(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    Post
    |> repo().get!(id)
    |> repo().preload(preloads)
  end

  @doc """
  Gets a single post by ID with optional preloads.

  Returns `nil` if post not found.

  ## Parameters

  - `id` - Post ID (UUIDv7)
  - `opts` - Options
    - `:preload` - List of associations to preload

  ## Examples

      iex> get_post("018e3c4a-...")
      %Post{}

      iex> get_post("018e3c4a-...", preload: [:user, :media, :tags])
      %Post{user: %User{}, media: [...], tags: [...]}

      iex> get_post("nonexistent")
      nil
  """
  def get_post(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case repo().get(Post, id) do
      nil -> nil
      post -> repo().preload(post, preloads)
    end
  end

  @doc """
  Gets a single post by slug.

  ## Parameters

  - `slug` - Post slug (e.g., "my-first-post")
  - `opts` - Options
    - `:preload` - List of associations to preload

  ## Examples

      iex> get_post_by_slug("my-first-post")
      %Post{}

      iex> get_post_by_slug("nonexistent")
      nil
  """
  def get_post_by_slug(slug, opts \\ []) when is_binary(slug) do
    preloads = Keyword.get(opts, :preload, [])

    Post
    |> where([p], p.slug == ^slug)
    |> repo().one()
    |> case do
      nil -> nil
      post -> repo().preload(post, preloads)
    end
  end

  @doc """
  Lists posts with optional filtering and pagination.

  ## Parameters

  - `opts` - Options
    - `:user_uuid` - Filter by user
    - `:status` - Filter by status (draft/public/unlisted/scheduled)
    - `:type` - Filter by type (post/snippet/repost)
    - `:search` - Search in title and content
    - `:page` - Page number (default: 1)
    - `:per_page` - Items per page (default: 20)
    - `:preload` - Associations to preload

  ## Examples

      iex> list_posts()
      [%Post{}, ...]

      iex> list_posts(status: "public", page: 1, per_page: 10)
      [%Post{}, ...]

      iex> list_posts(user_uuid: "018e3c4a-9f6b-7890-abcd-ef1234567890", type: "post")
      [%Post{}, ...]
  """
  def list_posts(opts \\ []) do
    user_uuid = Keyword.get(opts, :user_uuid)
    status = Keyword.get(opts, :status)
    type = Keyword.get(opts, :type)
    search = Keyword.get(opts, :search)
    page = Keyword.get(opts, :page)
    per_page = Keyword.get(opts, :per_page)
    preloads = Keyword.get(opts, :preload, [])

    Post
    |> maybe_filter_by_user(user_uuid)
    |> maybe_filter_by_status(status)
    |> maybe_filter_by_type(type)
    |> maybe_search(search)
    |> order_by([p], desc: p.inserted_at)
    |> maybe_paginate(page, per_page)
    |> repo().all()
    |> repo().preload(preloads)
  end

  @doc """
  Counts posts matching the given filter options.

  Accepts the same filter options as `list_posts/1` (`:user_uuid`, `:status`, `:type`, `:search`)
  but ignores pagination options.
  """
  def count_posts(opts \\ []) do
    user_uuid = Keyword.get(opts, :user_uuid)
    status = Keyword.get(opts, :status)
    type = Keyword.get(opts, :type)
    search = Keyword.get(opts, :search)

    Post
    |> maybe_filter_by_user(user_uuid)
    |> maybe_filter_by_status(status)
    |> maybe_filter_by_type(type)
    |> maybe_search(search)
    |> repo().aggregate(:count)
  rescue
    _ -> 0
  end

  @doc """
  Lists user's posts.

  ## Parameters

  - `user_uuid` - User UUID (UUIDv7 string)
  - `opts` - See `list_posts/1` for options

  ## Examples

      iex> list_user_posts("019145a1-...")
      [%Post{}, ...]
  """
  def list_user_posts(user_uuid, opts \\ [])

  def list_user_posts(user_uuid, opts) when is_binary(user_uuid) do
    list_posts(Keyword.put(opts, :user_uuid, user_uuid))
  end

  @doc """
  Lists public posts only.

  ## Parameters

  - `opts` - See `list_posts/1` for options

  ## Examples

      iex> list_public_posts()
      [%Post{}, ...]
  """
  def list_public_posts(opts \\ []) do
    opts = Keyword.put(opts, :status, "public")
    list_posts(opts)
  end

  # ============================================================================
  # Publishing Operations
  # ============================================================================

  @doc """
  Publishes a post (makes it public).

  Sets status to "public" and published_at to current time.

  ## Examples

      iex> publish_post(post)
      {:ok, %Post{status: "public"}}
  """
  def publish_post(%Post{} = post) do
    update_post(post, %{
      status: "public",
      published_at: UtilsDate.utc_now()
    })
  end

  @doc """
  Schedules a post for future publishing.

  Updates the post status to "scheduled" and creates an entry in the
  scheduled jobs table for execution by the cron worker.

  ## Parameters

  - `post` - Post to schedule
  - `scheduled_at` - DateTime to publish at (must be in future)
  - `attrs` - Additional attributes to update (title, content, etc.)
  - `opts` - Options
    - `:created_by_uuid` - UUID of user scheduling the post

  ## Examples

      iex> schedule_post(post, ~U[2025-12-31 09:00:00Z])
      {:ok, %Post{status: "scheduled"}}

      iex> schedule_post(post, ~U[2025-12-31 09:00:00Z], %{title: "New Title"})
      {:ok, %Post{status: "scheduled", title: "New Title"}}
  """
  def schedule_post(%Post{} = post, %DateTime{} = scheduled_at, attrs \\ %{}, opts \\ []) do
    repo().transaction(fn ->
      # Merge additional attrs with status and scheduled_at
      update_attrs =
        attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.merge(%{"status" => "scheduled", "scheduled_at" => scheduled_at})

      # Update the post with all attrs
      case update_post(post, update_attrs) do
        {:ok, updated_post} ->
          Logger.debug("Posts.schedule_post: Post status updated to 'scheduled'")

          # Cancel any existing pending scheduled jobs for this post
          {cancelled_count, _} = ScheduledJobs.cancel_jobs_for_resource("post", post.uuid)

          if cancelled_count > 0 do
            Logger.debug(
              "Posts.schedule_post: Cancelled #{cancelled_count} existing scheduled job(s)"
            )
          end

          # Create new scheduled job entry with useful context
          job_args = %{
            "post_title" => updated_post.title,
            "post_type" => updated_post.type,
            "post_status" => updated_post.status,
            "scheduled_for" => DateTime.to_iso8601(scheduled_at)
          }

          case ScheduledJobs.schedule_job(
                 ScheduledPostHandler,
                 post.uuid,
                 scheduled_at,
                 job_args,
                 opts
               ) do
            {:ok, job} ->
              Logger.info(
                "Posts.schedule_post: Created scheduled job #{job.id} for post #{post.uuid}"
              )

              updated_post

            {:error, reason} ->
              Logger.error(
                "Posts.schedule_post: Failed to create scheduled job: #{inspect(reason)}"
              )

              repo().rollback(reason)
          end

        {:error, changeset} ->
          Logger.error("Posts.schedule_post: Failed to update post: #{inspect(changeset.errors)}")
          repo().rollback(changeset)
      end
    end)
  end

  @doc """
  Unschedules a post, reverting it to draft status.

  Cancels any pending scheduled jobs for this post.

  ## Parameters

  - `post` - Post to unschedule

  ## Examples

      iex> unschedule_post(post)
      {:ok, %Post{status: "draft"}}
  """
  def unschedule_post(%Post{} = post) do
    repo().transaction(fn ->
      # Cancel any pending scheduled jobs
      ScheduledJobs.cancel_jobs_for_resource("post", post.uuid)

      # Revert to draft status
      case update_post(post, %{status: "draft", scheduled_at: nil}) do
        {:ok, updated_post} -> updated_post
        {:error, changeset} -> repo().rollback(changeset)
      end
    end)
  end

  @doc """
  Reverts a post to draft status.

  ## Examples

      iex> draft_post(post)
      {:ok, %Post{status: "draft"}}
  """
  def draft_post(%Post{} = post) do
    update_post(post, %{status: "draft"})
  end

  @doc """
  Processes scheduled posts that are ready to be published.

  Finds all posts with status "scheduled" where scheduled_at <= now,
  and publishes them. Returns list of published posts.

  Should be called periodically (e.g., via Oban job every minute).

  ## Examples

      iex> process_scheduled_posts()
      {:ok, 2}
  """
  def process_scheduled_posts do
    now = UtilsDate.utc_now()

    posts_to_publish =
      from(p in Post,
        where: p.status == "scheduled",
        where: p.scheduled_at <= ^now
      )
      |> repo().all(log: false)

    results = Enum.map(posts_to_publish, &publish_post/1)
    published_count = Enum.count(results, &match?({:ok, _}, &1))

    {:ok, published_count}
  end

  # ============================================================================
  # Counter Cache Operations
  # ============================================================================

  @doc """
  Increments the like counter for a post.

  ## Examples

      iex> increment_like_count(post)
      {1, nil}
  """
  def increment_like_count(%Post{uuid: id}) do
    from(p in Post, where: p.uuid == ^id)
    |> repo().update_all(inc: [like_count: 1])
  end

  @doc """
  Decrements the like counter for a post.

  ## Examples

      iex> decrement_like_count(post)
      {1, nil}
  """
  def decrement_like_count(%Post{uuid: id}) do
    from(p in Post, where: p.uuid == ^id and p.like_count > 0)
    |> repo().update_all(inc: [like_count: -1])
  end

  @doc """
  Increments the dislike counter for a post.

  ## Examples

      iex> increment_dislike_count(post)
      {1, nil}
  """
  def increment_dislike_count(%Post{uuid: id}) do
    from(p in Post, where: p.uuid == ^id)
    |> repo().update_all(inc: [dislike_count: 1])
  end

  @doc """
  Decrements the dislike counter for a post.

  ## Examples

      iex> decrement_dislike_count(post)
      {1, nil}
  """
  def decrement_dislike_count(%Post{uuid: id}) do
    from(p in Post, where: p.uuid == ^id and p.dislike_count > 0)
    |> repo().update_all(inc: [dislike_count: -1])
  end

  @doc """
  Increments the comment counter for a post.

  ## Examples

      iex> increment_comment_count(post)
      {1, nil}
  """
  def increment_comment_count(%Post{uuid: id}) do
    from(p in Post, where: p.uuid == ^id)
    |> repo().update_all(inc: [comment_count: 1])
  end

  @doc """
  Decrements the comment counter for a post.

  ## Examples

      iex> decrement_comment_count(post)
      {1, nil}
  """
  def decrement_comment_count(%Post{uuid: id}) do
    from(p in Post, where: p.uuid == ^id and p.comment_count > 0)
    |> repo().update_all(inc: [comment_count: -1])
  end

  @doc """
  Increments the view counter for a post.

  ## Examples

      iex> increment_view_count(post)
      {1, nil}
  """
  def increment_view_count(%Post{uuid: id}) do
    from(p in Post, where: p.uuid == ^id)
    |> repo().update_all(inc: [view_count: 1])
  end

  # ============================================================================
  # Like Operations
  # ============================================================================

  @doc """
  User likes a post.

  Creates a like record and increments the post's like counter.
  Returns error if user already liked the post.
  """
  def like_post(post_uuid, user_uuid) when is_binary(user_uuid) do
    if UUIDUtils.valid?(user_uuid) do
      do_like_post(post_uuid, user_uuid)
    else
      {:error, :invalid_user_uuid}
    end
  end

  defp do_like_post(post_uuid, user_uuid) do
    repo().transaction(fn ->
      # Remove existing dislike if present (mutual exclusion)
      case repo().get_by(PostDislike, post_uuid: post_uuid, user_uuid: user_uuid) do
        nil -> :ok
        dislike ->
          {:ok, _} = repo().delete(dislike)
          decrement_dislike_count(%Post{uuid: post_uuid})
      end

      case %PostLike{}
           |> PostLike.changeset(%{
             post_uuid: post_uuid,
             user_uuid: user_uuid
           })
           |> repo().insert() do
        {:ok, like} ->
          increment_like_count(%Post{uuid: post_uuid})
          like

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  @doc """
  User unlikes a post.

  Deletes the like record and decrements the post's like counter.
  Returns error if like doesn't exist.
  """
  def unlike_post(post_uuid, user_uuid) when is_binary(user_uuid) do
    if UUIDUtils.valid?(user_uuid) do
      do_unlike_post(post_uuid, user_uuid)
    else
      {:error, :invalid_user_uuid}
    end
  end

  defp do_unlike_post(post_uuid, user_uuid) do
    repo().transaction(fn ->
      case repo().get_by(PostLike, post_uuid: post_uuid, user_uuid: user_uuid) do
        nil ->
          repo().rollback(:not_found)

        like ->
          {:ok, _} = repo().delete(like)
          decrement_like_count(%Post{uuid: post_uuid})
          like
      end
    end)
  end

  @doc """
  Checks if a user has liked a post.
  """
  def post_liked_by?(post_uuid, user_uuid) when is_binary(user_uuid) do
    if UUIDUtils.valid?(user_uuid) do
      repo().exists?(
        from(l in PostLike, where: l.post_uuid == ^post_uuid and l.user_uuid == ^user_uuid)
      )
    else
      false
    end
  end

  @doc """
  Lists all likes for a post.
  """
  def list_post_likes(post_uuid, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    from(l in PostLike, where: l.post_uuid == ^post_uuid, order_by: [desc: l.inserted_at])
    |> repo().all()
    |> repo().preload(preloads)
  end

  # ============================================================================
  # Post Dislike Operations
  # ============================================================================

  @doc """
  User dislikes a post.
  """
  def dislike_post(post_uuid, user_uuid) when is_binary(user_uuid) do
    if UUIDUtils.valid?(user_uuid) do
      do_dislike_post(post_uuid, user_uuid)
    else
      {:error, :invalid_user_uuid}
    end
  end

  defp do_dislike_post(post_uuid, user_uuid) do
    repo().transaction(fn ->
      # Remove existing like if present (mutual exclusion)
      case repo().get_by(PostLike, post_uuid: post_uuid, user_uuid: user_uuid) do
        nil -> :ok
        like ->
          {:ok, _} = repo().delete(like)
          decrement_like_count(%Post{uuid: post_uuid})
      end

      case %PostDislike{}
           |> PostDislike.changeset(%{
             post_uuid: post_uuid,
             user_uuid: user_uuid
           })
           |> repo().insert() do
        {:ok, dislike} ->
          increment_dislike_count(%Post{uuid: post_uuid})
          dislike

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  @doc """
  User removes dislike from a post.
  """
  def undislike_post(post_uuid, user_uuid) when is_binary(user_uuid) do
    if UUIDUtils.valid?(user_uuid) do
      do_undislike_post(post_uuid, user_uuid)
    else
      {:error, :invalid_user_uuid}
    end
  end

  defp do_undislike_post(post_uuid, user_uuid) do
    repo().transaction(fn ->
      case repo().get_by(PostDislike, post_uuid: post_uuid, user_uuid: user_uuid) do
        nil ->
          repo().rollback(:not_found)

        dislike ->
          {:ok, _} = repo().delete(dislike)
          decrement_dislike_count(%Post{uuid: post_uuid})
          dislike
      end
    end)
  end

  @doc """
  Checks if a user has disliked a post.
  """
  def post_disliked_by?(post_uuid, user_uuid) when is_binary(user_uuid) do
    if UUIDUtils.valid?(user_uuid) do
      repo().exists?(
        from(d in PostDislike, where: d.post_uuid == ^post_uuid and d.user_uuid == ^user_uuid)
      )
    else
      false
    end
  end

  @doc """
  Lists all dislikes for a post.
  """
  def list_post_dislikes(post_uuid, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    from(d in PostDislike, where: d.post_uuid == ^post_uuid, order_by: [desc: d.inserted_at])
    |> repo().all()
    |> repo().preload(preloads)
  end

  # ============================================================================
  # Comment Resource Handler Callbacks
  # ============================================================================

  @doc """
  Callback invoked by the Comments module when a comment is created on a post.
  Increments the post's denormalized comment_count.
  """
  def on_comment_created("post", resource_uuid, _comment) do
    increment_comment_count(%Post{uuid: resource_uuid})
    :ok
  end

  def on_comment_created(_resource_type, _resource_uuid, _comment), do: :ok

  @doc """
  Callback invoked by the Comments module when a comment is deleted from a post.
  Decrements the post's denormalized comment_count.
  """
  def on_comment_deleted("post", resource_uuid, _comment) do
    decrement_comment_count(%Post{uuid: resource_uuid})
    :ok
  end

  def on_comment_deleted(_resource_type, _resource_uuid, _comment), do: :ok

  @doc """
  Resolves post titles and admin paths for a list of resource IDs.

  Called by the Comments module to display resource context in the admin UI.
  Returns a map of `resource_uuid => %{title: ..., path: ...}`.
  """
  def resolve_comment_resources(resource_uuids) when is_list(resource_uuids) do
    from(p in Post, where: p.uuid in ^resource_uuids, select: {p.uuid, p.title})
    |> repo().all()
    |> Map.new(fn {uuid, title} -> {uuid, %{title: title, path: "/admin/posts/#{uuid}"}} end)
  rescue
    _ -> %{}
  end

  # ============================================================================
  # Tag Operations
  # ============================================================================

  @doc """
  Finds or creates a tag by name.

  Automatically generates slug from name. Returns existing tag if slug already exists.
  """
  def find_or_create_tag(name) when is_binary(name) do
    changeset = PostTag.changeset(%PostTag{}, %{name: name})
    slug = Ecto.Changeset.get_field(changeset, :slug)

    case repo().get_by(PostTag, slug: slug) do
      nil -> repo().insert(changeset)
      tag -> {:ok, tag}
    end
  end

  @doc """
  Parses hashtags from text.

  Extracts all hashtags (#word) from text and returns list of tag names.
  """
  def parse_hashtags(text) when is_binary(text) do
    ~r/#(\w+)/
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc """
  Adds tags to a post.

  Creates tags if they don't exist, then assigns them to the post.
  Updates usage counters for tags.
  """
  def add_tags_to_post(%Post{uuid: post_uuid}, tag_names) when is_list(tag_names) do
    repo().transaction(fn ->
      tags =
        Enum.map(tag_names, fn name ->
          case find_or_create_tag(name) do
            {:ok, tag} -> tag
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      Enum.each(tags, fn tag ->
        case %PostTagAssignment{}
             |> PostTagAssignment.changeset(%{post_uuid: post_uuid, tag_uuid: tag.uuid})
             |> repo().insert(on_conflict: :nothing) do
          {:ok, %{uuid: nil}} ->
            # on_conflict: :nothing returns a struct with nil PK — assignment already existed
            :ok

          {:ok, _assignment} ->
            # New assignment — increment tag usage
            from(t in PostTag, where: t.uuid == ^tag.uuid)
            |> repo().update_all(inc: [usage_count: 1])

          _ ->
            :ok
        end
      end)

      tags
    end)
  end

  @doc """
  Removes a tag from a post.
  """
  def remove_tag_from_post(post_uuid, tag_uuid) do
    case repo().get_by(PostTagAssignment, post_uuid: post_uuid, tag_uuid: tag_uuid) do
      nil ->
        {:error, :not_found}

      assignment ->
        repo().transaction(fn ->
          repo().delete(assignment)

          # Decrement tag usage
          from(t in PostTag, where: t.uuid == ^tag_uuid and t.usage_count > 0)
          |> repo().update_all(inc: [usage_count: -1])

          assignment
        end)
    end
  end

  @doc """
  Lists popular tags by usage count.
  """
  def list_popular_tags(limit \\ 20) do
    from(t in PostTag, order_by: [desc: t.usage_count], limit: ^limit)
    |> repo().all()
  end

  # ============================================================================
  # Group Operations
  # ============================================================================

  @doc """
  Creates a user group.
  """
  def create_group(user_uuid, attrs) when is_binary(user_uuid) do
    create_group_with_uuid(user_uuid, attrs)
  end

  defp create_group_with_uuid(user_uuid, attrs) do
    case Auth.get_user(user_uuid) do
      %{uuid: uuid} ->
        attrs =
          attrs
          |> Map.put(:user_uuid, uuid)

        %PostGroup{}
        |> PostGroup.changeset(attrs)
        |> repo().insert()

      nil ->
        {:error, :user_not_found}
    end
  end

  @doc """
  Updates a group.
  """
  def update_group(%PostGroup{} = group, attrs) do
    group
    |> PostGroup.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a group.
  """
  def delete_group(%PostGroup{} = group) do
    repo().delete(group)
  end

  @doc """
  Gets a single group by ID with optional preloads.

  Returns `nil` if group not found.
  """
  def get_group(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case repo().get(PostGroup, id) do
      nil -> nil
      group -> repo().preload(group, preloads)
    end
  end

  @doc """
  Gets a single group by ID with optional preloads.

  Raises `Ecto.NoResultsError` if group not found.
  """
  def get_group!(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    PostGroup
    |> repo().get!(id)
    |> repo().preload(preloads)
  end

  @doc """
  Adds a post to a group.
  """
  def add_post_to_group(post_uuid, group_uuid, opts \\ []) do
    position = Keyword.get(opts, :position, 0)

    repo().transaction(fn ->
      case %PostGroupAssignment{}
           |> PostGroupAssignment.changeset(%{
             post_uuid: post_uuid,
             group_uuid: group_uuid,
             position: position
           })
           |> repo().insert() do
        {:ok, assignment} ->
          from(g in PostGroup, where: g.uuid == ^group_uuid)
          |> repo().update_all(inc: [post_count: 1])

          assignment

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  @doc """
  Adds multiple posts to a group in a single transaction.
  """
  def add_posts_to_group(post_uuids, group_uuid, opts \\ []) do
    position = Keyword.get(opts, :position, 0)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(post_uuids, fn post_uuid ->
        %{
          post_uuid: post_uuid,
          group_uuid: group_uuid,
          position: position,
          inserted_at: now,
          updated_at: now
        }
      end)

    repo().transaction(fn ->
      {inserted_count, _} =
        repo().insert_all(PostGroupAssignment, entries, on_conflict: :nothing)

      if inserted_count > 0 do
        from(g in PostGroup, where: g.uuid == ^group_uuid)
        |> repo().update_all(inc: [post_count: inserted_count])
      end

      inserted_count
    end)
  end

  @doc """
  Removes a post from a group.
  """
  def remove_post_from_group(post_uuid, group_uuid) do
    case repo().get_by(PostGroupAssignment, post_uuid: post_uuid, group_uuid: group_uuid) do
      nil ->
        {:error, :not_found}

      assignment ->
        repo().transaction(fn ->
          repo().delete(assignment)

          from(g in PostGroup, where: g.uuid == ^group_uuid and g.post_count > 0)
          |> repo().update_all(inc: [post_count: -1])

          assignment
        end)
    end
  end

  @doc """
  Lists user's groups.
  """
  def list_user_groups(user_uuid, opts \\ [])

  def list_user_groups(user_uuid, opts) when is_binary(user_uuid) do
    list_user_groups_by_uuid(user_uuid, opts)
  end

  defp list_user_groups_by_uuid(user_uuid, opts) do
    preloads = Keyword.get(opts, :preload, [])

    from(g in PostGroup, where: g.user_uuid == ^user_uuid, order_by: [asc: g.position])
    |> repo().all()
    |> repo().preload(preloads)
  end

  @doc """
  Lists all groups ordered by name.
  """
  def list_groups(opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    from(g in PostGroup, order_by: [asc: g.name])
    |> repo().all()
    |> repo().preload(preloads)
  end

  @doc """
  Lists posts in a group.
  """
  def list_posts_by_group(group_uuid, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    from(p in Post,
      join: ga in PostGroupAssignment,
      on: ga.post_uuid == p.uuid,
      where: ga.group_uuid == ^group_uuid,
      order_by: [asc: ga.position]
    )
    |> repo().all()
    |> repo().preload(preloads)
  end

  @doc """
  Reorders user's groups.
  """
  def reorder_groups(user_uuid, group_uuid_positions) when is_map(group_uuid_positions) do
    case repo().transaction(fn ->
           Enum.each(group_uuid_positions, fn {group_uuid, position} ->
             from(g in PostGroup, where: g.uuid == ^group_uuid and g.user_uuid == ^user_uuid)
             |> repo().update_all(set: [position: position])
           end)
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Mention Operations
  # ============================================================================

  @doc """
  Adds a mention to a post.
  """
  def add_mention_to_post(post_uuid, user_uuid, mention_type \\ "mention")

  def add_mention_to_post(post_uuid, user_uuid, mention_type) when is_binary(user_uuid) do
    if UUIDUtils.valid?(user_uuid) do
      %PostMention{}
      |> PostMention.changeset(%{
        post_uuid: post_uuid,
        user_uuid: user_uuid,
        mention_type: mention_type
      })
      |> repo().insert()
    else
      {:error, :invalid_user_uuid}
    end
  end

  @doc """
  Removes a mention from a post.
  """
  def remove_mention_from_post(post_uuid, user_uuid) when is_binary(user_uuid) do
    if UUIDUtils.valid?(user_uuid) do
      do_remove_mention(post_uuid, user_uuid)
    else
      {:error, :invalid_user_uuid}
    end
  end

  defp do_remove_mention(post_uuid, user_uuid) do
    case repo().get_by(PostMention, post_uuid: post_uuid, user_uuid: user_uuid) do
      nil -> {:error, :not_found}
      mention -> repo().delete(mention)
    end
  end

  @doc """
  Lists mentioned users in a post.
  """
  def list_post_mentions(post_uuid, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    from(m in PostMention, where: m.post_uuid == ^post_uuid)
    |> repo().all()
    |> repo().preload(preloads)
  end

  # ============================================================================
  # Media Operations
  # ============================================================================

  @doc """
  Attaches media to a post.
  """
  def attach_media(post_uuid, file_uuid, opts \\ []) do
    position = Keyword.get(opts, :position, 1)
    caption = Keyword.get(opts, :caption)

    %PostMedia{}
    |> PostMedia.changeset(%{
      post_uuid: post_uuid,
      file_uuid: file_uuid,
      position: position,
      caption: caption
    })
    |> repo().insert()
  end

  @doc """
  Detaches media from a post.
  """
  def detach_media(post_uuid, file_uuid) do
    case repo().get_by(PostMedia, post_uuid: post_uuid, file_uuid: file_uuid) do
      nil -> {:error, :not_found}
      media -> repo().delete(media)
    end
  end

  @doc """
  Detaches media from a post by PostMedia ID.
  """
  def detach_media_by_uuid(media_uuid) do
    case repo().get(PostMedia, media_uuid) do
      nil -> {:error, :not_found}
      media -> repo().delete(media)
    end
  end

  @doc """
  Lists media for a post (ordered by position).
  """
  def list_post_media(post_uuid, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [:file])

    from(m in PostMedia, where: m.post_uuid == ^post_uuid, order_by: [asc: m.position])
    |> repo().all()
    |> repo().preload(preloads)
  end

  @doc """
  Reorders media in a post.
  """
  def reorder_media(post_uuid, file_uuid_positions) when is_map(file_uuid_positions) do
    case repo().transaction(fn ->
           # Two-pass approach to avoid unique constraint violations on (post_id, position)
           # Pass 1: Set all positions to negative values (temporary)
           Enum.each(file_uuid_positions, fn {file_uuid, position} ->
             from(m in PostMedia, where: m.post_uuid == ^post_uuid and m.file_uuid == ^file_uuid)
             |> repo().update_all(set: [position: -position])
           end)

           # Pass 2: Set the correct positive positions
           Enum.each(file_uuid_positions, fn {file_uuid, position} ->
             from(m in PostMedia, where: m.post_uuid == ^post_uuid and m.file_uuid == ^file_uuid)
             |> repo().update_all(set: [position: position])
           end)
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets the featured image for a post (PostMedia with position 1).
  """
  def set_featured_image(post_uuid, file_uuid) do
    repo().transaction(fn ->
      # Remove existing featured image if present
      from(m in PostMedia, where: m.post_uuid == ^post_uuid and m.position == 1)
      |> repo().delete_all()

      # Insert new featured image at position 1
      case %PostMedia{}
           |> PostMedia.changeset(%{
             post_uuid: post_uuid,
             file_uuid: file_uuid,
             position: 1
           })
           |> repo().insert() do
        {:ok, media} -> media
        {:error, changeset} -> repo().rollback(changeset)
      end
    end)
  end

  @doc """
  Gets the featured image for a post (PostMedia with position 1).
  """
  def get_featured_image(post_uuid) do
    from(m in PostMedia,
      where: m.post_uuid == ^post_uuid and m.position == 1,
      preload: [:file]
    )
    |> repo().one()
  end

  @doc """
  Removes the featured image from a post.
  """
  def remove_featured_image(post_uuid) do
    {count, _} =
      from(m in PostMedia, where: m.post_uuid == ^post_uuid and m.position == 1)
      |> repo().delete_all()

    {:ok, count}
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp maybe_filter_by_user(query, nil), do: query

  defp maybe_filter_by_user(query, user_uuid) when is_binary(user_uuid) do
    where(query, [p], p.user_uuid == ^user_uuid)
  end

  defp maybe_filter_by_status(query, nil), do: query

  defp maybe_filter_by_status(query, status) do
    where(query, [p], p.status == ^status)
  end

  defp maybe_filter_by_type(query, nil), do: query

  defp maybe_filter_by_type(query, type) do
    where(query, [p], p.type == ^type)
  end

  defp maybe_search(query, nil), do: query

  defp maybe_search(query, search_term) do
    search_pattern = "%#{search_term}%"

    where(
      query,
      [p],
      ilike(p.title, ^search_pattern) or ilike(p.content, ^search_pattern)
    )
  end

  defp maybe_paginate(query, nil, _per_page), do: query
  defp maybe_paginate(query, _page, nil), do: query

  defp maybe_paginate(query, page, per_page) when is_integer(page) and is_integer(per_page) do
    offset = (page - 1) * per_page

    query
    |> limit(^per_page)
    |> offset(^offset)
  end

  # Get repository based on configuration (for tests and apps with custom repos)
  defp repo do
    PhoenixKit.RepoHelper.repo()
  end
end
