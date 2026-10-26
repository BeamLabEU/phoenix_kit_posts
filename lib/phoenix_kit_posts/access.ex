defmodule PhoenixKitPosts.Access do
  @moduledoc """
  Who may see and act on a post. Every LiveView asks here, so the list, the
  details page, the bulk actions and the editor apply one rule.

    * **Act** (edit, delete, publish, unpublish, change status, add to a
      group): the post's author, or a holder of `posts.manage_all`.
    * **See**: the author, anyone while the post is published (`public` or
      `unlisted`), or a holder of `posts.view_all` or `posts.manage_all`.
      The admin list shows other people's unpublished posts only with
      `posts.view_all`.
    * **See the author's email**: the author, or a holder of `posts.view_all`.
    * **Change the module's settings**: a holder of `posts.settings`.

  Checks go through `PhoenixKit.Users.Auth.Scope.can?/2`, so Owner (who holds
  no permission rows) passes and a disabled module grants nothing.
  """

  alias PhoenixKit.Users.Auth.Scope

  @manage_all "posts.manage_all"
  @view_all "posts.view_all"
  @settings "posts.settings"

  @published ~w(public unlisted)

  @doc "The key that lets a user act on other people's posts."
  def manage_all_key, do: @manage_all

  @doc "The key that lets a user see other people's unpublished posts and authors' emails."
  def view_all_key, do: @view_all

  @doc "The key that guards the module's settings page."
  def settings_key, do: @settings

  @doc "Statuses anyone holding `posts` may see on another user's post."
  def published_statuses, do: @published

  @doc "True when the scope may edit, delete, publish or unpublish `post`."
  def can_manage_post?(scope, post) do
    own_post?(scope, post) or Scope.can?(scope, @manage_all)
  end

  @doc "True when the scope may see `post` at all."
  def can_view_post?(scope, post) do
    own_post?(scope, post) or Map.get(post, :status) in @published or
      Scope.can?(scope, @view_all) or Scope.can?(scope, @manage_all)
  end

  @doc "True when the scope may see the email of `post`'s author."
  def can_see_author_email?(scope, post) do
    own_post?(scope, post) or Scope.can?(scope, @view_all)
  end

  @doc "True when the scope may see every post in the admin list, drafts included."
  def view_all?(scope), do: Scope.can?(scope, @view_all)

  @doc "True when the scope may open and save the settings page."
  def can_change_settings?(scope), do: Scope.can?(scope, @settings)

  @doc """
  The `list_posts/1` / `count_posts/1` option that limits a listing to what
  the scope may see: nothing for a `posts.view_all` holder, otherwise
  `visible_to: user_uuid` (own posts plus published ones).
  """
  def list_opts(scope) do
    if view_all?(scope), do: [], else: [visible_to: Scope.user_uuid(scope)]
  end

  defp own_post?(scope, post) do
    case Scope.user_uuid(scope) do
      nil -> false
      uuid -> Map.get(post, :user_uuid) == uuid
    end
  end
end
