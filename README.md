# PhoenixKitPosts

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_kit_posts.svg)](https://hex.pm/packages/phoenix_kit_posts)

Posts module for [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit) — blog posts, comments, tags, groups, likes, media, mentions, view tracking, and scheduled publishing.

## Requirements

- Elixir ~> 1.18
- [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit) ~> 1.7 (host application)
- Phoenix LiveView ~> 1.1

## Installation

Add to your parent PhoenixKit app's `mix.exs`:

```elixir
{:phoenix_kit_posts, "~> 0.1.0"}
```

Run `mix deps.get`. The module appears in the admin panel automatically via PhoenixKit's auto-discovery — no additional configuration required.

## Features

- **Post management** — Create, update, delete, publish posts with draft/public/unlisted/scheduled status
- **Threaded comments** — Nested comments with unlimited depth, plus like/dislike tracking per comment
- **Like and dislike system** — One-per-user enforcement with denormalized counter caches
- **Tag system** — Hashtag parsing and auto-slugification
- **Group collections** — Pinterest-style boards for organizing posts with ordering
- **Media attachments** — Multiple files per post with position-based ordering and featured image support
- **User mentions** — Track @mentions within posts
- **View tracking** — Track post views with denormalized counters
- **Scheduled publishing** — Automatic publishing at a specified time via [Oban](https://github.com/sorentwo/oban) workers
- **Admin UI** — LiveView-based admin pages for posts, groups, and settings

## Usage

```elixir
# Create a post
{:ok, post} = PhoenixKitPosts.create_post(user_uuid, %{
  title: "My First Post",
  content: "Hello world!",
  type: "post",
  status: "draft"
})

# Publish a post
{:ok, post} = PhoenixKitPosts.publish_post(post)

# Schedule a post for later
{:ok, post} = PhoenixKitPosts.schedule_post(post, ~U[2026-04-01 12:00:00Z])

# Like a post (one per user, enforced by unique constraint)
{:ok, like} = PhoenixKitPosts.like_post(post.uuid, user_uuid)

# Tag a post
PhoenixKitPosts.add_tags_to_post(post, ["elixir", "phoenix"])

# Create a group and organize posts
{:ok, group} = PhoenixKitPosts.create_group(user_uuid, %{
  name: "Travel Photos",
  description: "My adventures"
})
PhoenixKitPosts.add_post_to_group(post.uuid, group.uuid)

# Attach media
PhoenixKitPosts.attach_media(post.uuid, file_uuid, position: 1)

# Mention a user
PhoenixKitPosts.add_mention_to_post(post.uuid, mentioned_user_uuid)

# Query posts
posts = PhoenixKitPosts.list_public_posts(page: 1, per_page: 20)
post = PhoenixKitPosts.get_post_by_slug("my-first-post")
```

## Configuration

Settings are managed through the PhoenixKit Settings API and can be configured via the admin UI at `/admin/settings/posts`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `posts_enabled` | boolean | `true` | Enable/disable the module |
| `posts_per_page` | integer | `20` | Posts per page in admin listing |
| `posts_default_status` | string | `"draft"` | Default status for new posts |
| `posts_likes_enabled` | boolean | `true` | Enable/disable like system |
| `posts_allow_scheduling` | boolean | `true` | Allow scheduled publishing |
| `posts_allow_groups` | boolean | `true` | Allow post groups/boards |
| `posts_allow_reposts` | boolean | `true` | Allow reposting |
| `posts_seo_auto_slug` | boolean | `true` | Auto-generate URL slugs |
| `posts_show_view_count` | boolean | `true` | Show view counts publicly |
| `posts_require_approval` | boolean | `false` | Require admin approval |
| `posts_max_media` | integer | `10` | Max media attachments per post |
| `posts_max_title_length` | integer | `255` | Max title character length |
| `posts_max_subtitle_length` | integer | `500` | Max subtitle character length |
| `posts_max_content_length` | integer | `50000` | Max content character length |
| `posts_max_mentions` | integer | `10` | Max mentions per post |
| `posts_max_tags` | integer | `20` | Max tags per post |

## Documentation

Generate docs locally with:

```bash
mix docs
```

## Development

```bash
mix deps.get        # Install dependencies
mix test            # Run tests
mix format          # Format code
mix credo --strict  # Static analysis
mix dialyzer        # Type checking
mix precommit       # All of the above
```

## License

MIT — see [LICENSE](LICENSE) for details.

## Links

- [GitHub](https://github.com/BeamLabEU/phoenix_kit_posts)
- [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit)
