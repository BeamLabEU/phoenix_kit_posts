defmodule PhoenixKitPosts.Post do
  @moduledoc """
  Schema for user posts with media attachments.

  Represents a social post with type-specific layouts, privacy controls,
  and scheduled publishing support.

  ## Post Types

  - **post** - Standard full post with full content and media gallery
  - **snippet** - Short form post with truncated display
  - **repost** - Share of external content with source attribution

  ## Status Flow

  - `draft` - Post is being edited (not visible to others)
  - `public` - Post is published and visible to all
  - `unlisted` - Post is accessible via direct link but not in feeds
  - `scheduled` - Post will be auto-published at scheduled_at time

  ## Fields

  - `user_uuid` - Owner of the post
  - `title` - Post title (max length via settings)
  - `sub_title` - Subtitle/tagline (max length via settings)
  - `content` - Post content (max length via settings)
  - `type` - post/snippet/repost (affects display layout)
  - `status` - draft/public/unlisted/scheduled
  - `scheduled_at` - When to auto-publish (nullable)
  - `published_at` - When made public (nullable)
  - `repost_url` - Source URL for reposts (nullable)
  - `slug` - SEO-friendly URL slug
  - `like_count` - Denormalized counter (updated via context)
  - `comment_count` - Denormalized counter (updated via context)
  - `view_count` - Page views counter (updated via context)
  - `metadata` - Type-specific flexible data (JSONB)

  ## Examples

      # Standard post
      %Post{
        id: "018e3c4a-9f6b-7890-abcd-ef1234567890",
        user_uuid: "018e3c4a-1234-5678-abcd-ef1234567890",
        title: "My First Post",
        sub_title: "An introduction to my journey",
        content: "This is the full content...",
        type: "post",
        status: "public",
        slug: "my-first-post",
        like_count: 42,
        comment_count: 15,
        view_count: 523,
        published_at: ~U[2025-01-01 12:00:00Z]
      }

      # Scheduled post
      %Post{
        title: "Future Announcement",
        content: "...",
        type: "post",
        status: "scheduled",
        scheduled_at: ~U[2025-12-31 09:00:00Z],
        published_at: nil
      }

      # Repost
      %Post{
        title: "Great Article",
        content: "Check this out!",
        type: "repost",
        status: "public",
        repost_url: "https://example.com/article",
        metadata: %{"original_author" => "Jane Doe"}
      }
  """
  use Ecto.Schema
  use PhoenixKit.SchemaPrefix
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias PhoenixKit.Utils.Date, as: UtilsDate
  alias PhoenixKit.Utils.Slug

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @type t :: %__MODULE__{
          uuid: UUIDv7.t() | nil,
          user_uuid: UUIDv7.t() | nil,
          title: String.t(),
          sub_title: String.t() | nil,
          content: String.t(),
          type: String.t(),
          status: String.t(),
          scheduled_at: DateTime.t() | nil,
          published_at: DateTime.t() | nil,
          repost_url: String.t() | nil,
          slug: String.t(),
          like_count: integer(),
          dislike_count: integer(),
          comment_count: integer(),
          view_count: integer(),
          metadata: map(),
          user: PhoenixKit.Users.Auth.User.t() | Ecto.Association.NotLoaded.t(),
          media: [PhoenixKitPosts.PostMedia.t()] | Ecto.Association.NotLoaded.t(),
          likes: [PhoenixKitPosts.PostLike.t()] | Ecto.Association.NotLoaded.t(),
          dislikes: [PhoenixKitPosts.PostDislike.t()] | Ecto.Association.NotLoaded.t(),
          comments: [PhoenixKitPosts.PostComment.t()] | Ecto.Association.NotLoaded.t(),
          mentions: [PhoenixKitPosts.PostMention.t()] | Ecto.Association.NotLoaded.t(),
          tags: [PhoenixKitPosts.PostTag.t()] | Ecto.Association.NotLoaded.t(),
          groups: [PhoenixKitPosts.PostGroup.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "phoenix_kit_posts" do
    field(:title, :string)
    field(:sub_title, :string)
    field(:content, :string)
    field(:type, :string, default: "post")
    field(:status, :string, default: "draft")
    field(:scheduled_at, :utc_datetime)
    field(:published_at, :utc_datetime)
    field(:repost_url, :string)
    field(:slug, :string)
    field(:like_count, :integer, default: 0)
    field(:dislike_count, :integer, default: 0)
    field(:comment_count, :integer, default: 0)
    field(:view_count, :integer, default: 0)
    field(:metadata, :map, default: %{})

    belongs_to(:user, PhoenixKit.Users.Auth.User,
      foreign_key: :user_uuid,
      references: :uuid,
      type: UUIDv7
    )

    has_many(:media, PhoenixKitPosts.PostMedia, foreign_key: :post_uuid)
    has_many(:likes, PhoenixKitPosts.PostLike, foreign_key: :post_uuid)
    has_many(:dislikes, PhoenixKitPosts.PostDislike, foreign_key: :post_uuid)
    has_many(:comments, PhoenixKitPosts.PostComment, foreign_key: :post_uuid)
    has_many(:mentions, PhoenixKitPosts.PostMention, foreign_key: :post_uuid)

    many_to_many(:tags, PhoenixKitPosts.PostTag,
      join_through: PhoenixKitPosts.PostTagAssignment,
      join_keys: [post_uuid: :uuid, tag_uuid: :uuid]
    )

    many_to_many(:groups, PhoenixKitPosts.PostGroup,
      join_through: PhoenixKitPosts.PostGroupAssignment,
      join_keys: [post_uuid: :uuid, group_uuid: :uuid]
    )

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a post.

  ## Required Fields

  - `user_uuid` - Owner of the post
  - `title` - Post title
  - `content` - Post content
  - `type` - Must be: "post", "snippet", or "repost"
  - `status` - Must be: "draft", "public", "unlisted", or "scheduled"

  ## Validation Rules

  - Title and content lengths validated against settings
  - Type must be valid (post/snippet/repost)
  - Status must be valid (draft/public/unlisted/scheduled)
  - Slug auto-generated from title if not provided
  - Scheduled posts must have scheduled_at
  - Reposts should have repost_url
  """
  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :user_uuid,
      :title,
      :sub_title,
      :content,
      :type,
      :status,
      :scheduled_at,
      :published_at,
      :repost_url,
      :slug,
      :metadata
    ])
    |> validate_required([:user_uuid, :title, :content, :type, :status])
    |> validate_inclusion(:type, ["post", "snippet", "repost"])
    |> validate_inclusion(:status, ["draft", "public", "unlisted", "scheduled"])
    |> validate_length(:title, max: 255)
    |> validate_length(:sub_title, max: 500)
    |> validate_scheduled_at()
    |> maybe_generate_slug()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:user_uuid)
  end

  @doc """
  Check if post is published (public or unlisted).
  """
  def published?(%__MODULE__{status: status}) when status in ["public", "unlisted"], do: true
  def published?(_), do: false

  @doc """
  Check if post is scheduled for future publishing.
  """
  def scheduled?(%__MODULE__{status: "scheduled"}), do: true
  def scheduled?(_), do: false

  @doc """
  Check if post can receive comments (public or unlisted).
  """
  def can_comment?(%__MODULE__{status: status}) when status in ["public", "unlisted"], do: true
  def can_comment?(_), do: false

  @doc """
  Check if post is a draft.
  """
  def draft?(%__MODULE__{status: "draft"}), do: true
  def draft?(_), do: false

  @doc """
  Check if post is a repost type.
  """
  def repost?(%__MODULE__{type: "repost"}), do: true
  def repost?(_), do: false

  # Private Functions

  defp validate_scheduled_at(changeset) do
    status = get_field(changeset, :status)
    scheduled_at = get_field(changeset, :scheduled_at)
    status_changed? = get_change(changeset, :status) != nil
    scheduled_at_changed? = get_change(changeset, :scheduled_at) != nil

    case {status, scheduled_at} do
      {"scheduled", nil} ->
        add_error(changeset, :scheduled_at, "must be set when status is scheduled")

      {"scheduled", datetime} when not is_nil(datetime) ->
        # Only validate scheduled_at is in the future if:
        # 1. scheduled_at is being changed, OR
        # 2. status is being changed TO "scheduled"
        # This allows editing other fields without re-validating an existing schedule
        if (scheduled_at_changed? or status_changed?) and
             DateTime.compare(datetime, UtilsDate.utc_now()) == :lt do
          add_error(changeset, :scheduled_at, "must be in the future")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  # An absent slug change means "unchanged", not "recompute it from the title".
  #
  # Reading `get_change(:slug)` conflated the two, so any save not itself
  # carrying a new slug re-slugified the title and overwrote a hand-picked one:
  # publishing, scheduling, unscheduling, drafting — and every ordinary title
  # edit in the admin UI, because the edit form re-sends the current slug and
  # `cast/3` drops a value equal to the data, leaving no change to find. A live
  # URL moved on almost any save, and nothing recorded the old one, so the page
  # 404'd.
  defp maybe_generate_slug(changeset) do
    case fetch_change(changeset, :slug) do
      # An explicit, non-blank slug from the caller always wins.
      {:ok, slug} when is_binary(slug) and slug != "" ->
        changeset

      # Explicitly blanked means "regenerate from the title" — the column is
      # NOT NULL, so persisting the blank is not an option.
      {:ok, _blank} ->
        changeset |> delete_change(:slug) |> put_slug_from(:title)

      # No slug in this changeset: generate only when the record hasn't got one.
      :error ->
        if changeset.data.slug in [nil, ""] do
          put_slug_from(changeset, :title)
        else
          changeset
        end
    end
  end

  defp put_slug_from(changeset, source) do
    case get_field(changeset, source) do
      value when is_binary(value) and value != "" ->
        case slugify(value) do
          "" -> changeset
          slug -> put_change(changeset, :slug, unique_slug(slug, changeset.data.uuid))
        end

      _ ->
        changeset
    end
  end

  # Two posts titled the same slugified identically, so nothing stopped
  # duplicate slugs from being created — and `get_post_by_slug/2` fetches with
  # `repo().one()`, which raises `Ecto.MultipleResultsError` the moment there
  # are two. Core's `Slug.ensure_unique/2` is the house rule: suffix -2, -3, …
  # until free. Romanization is lossy in every language, so collisions are
  # normal rather than exceptional and the suffix is the answer, not a better
  # transliteration table.
  #
  # The check is a query from a changeset, which is unusual but deliberate: it
  # is the same thing `Ecto.Changeset.unsafe_validate_unique/4` does, and the
  # alternative — generating in the schema and uniquifying in the context —
  # splits one decision across two modules. It stays advisory: a concurrent
  # insert between this probe and the write is still possible, which is what
  # the database's own unique index is for.
  defp unique_slug(slug, own_uuid) do
    Slug.ensure_unique(slug, fn candidate ->
      query = from(p in __MODULE__, where: p.slug == ^candidate)

      query =
        if own_uuid, do: from(p in query, where: p.uuid != ^own_uuid), else: query

      PhoenixKit.RepoHelper.repo().exists?(query)
    end)
  rescue
    # No repo configured, or it is unreachable. Slug generation is not the
    # place to take an application down, and the unsuffixed slug is what this
    # produced before uniqueness was considered at all.
    _ -> slug
  end

  # Core's rule, not a local copy. The pipeline this replaced stripped every
  # non-ASCII character, so a Cyrillic or Greek title produced an EMPTY slug and
  # German "Größe" lost its umlaut and its ß. `Slug.slugify/2` romanizes instead.
  #
  # Core 2.0's Slug delegates to `locale_slug` and IS locale-aware — German
  # expands "ö"/"ß" to "oe"/"ss", Estonian folds them to "o"/"s". No locale is
  # passed here because these schemas slug a single-language name and have no
  # language in scope; the result is still correct, just not locale-tuned. Pass
  # `locale:` from any caller that knows one.
  #
  # `transliterate: true` is redundant under core 2.0 (romanization is always on
  # and the option is accepted-and-ignored for source compatibility), kept so
  # this reads the same as every other slug site in the umbrella.
  defp slugify(title), do: Slug.slugify(title, transliterate: true)
end
