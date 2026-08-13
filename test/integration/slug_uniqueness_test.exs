defmodule PhoenixKitPosts.Integration.SlugUniquenessTest do
  @moduledoc """
  Generated slugs follow core's house rule: suffix -2, -3, … until free.

  These need the database because uniqueness is a question about other rows —
  which is why the gap survived so long in a repo with no DB harness.
  """
  use PhoenixKitPosts.DataCase, async: true

  alias PhoenixKitPosts.Post

  setup do
    %{user: user_fixture()}
  end

  defp create!(user, attrs) do
    {:ok, post} = PhoenixKitPosts.create_post(user.uuid, Map.merge(%{"content" => "Body"}, attrs))

    post
  end

  test "a second post with the same title gets -2, a third -3", %{user: user} do
    first = create!(user, %{"title" => "Same Title"})
    second = create!(user, %{"title" => "Same Title"})
    third = create!(user, %{"title" => "Same Title"})

    assert first.slug == "same-title"
    assert second.slug == "same-title-2"
    assert third.slug == "same-title-3"
  end

  test "get_post_by_slug/2 no longer has two rows to choke on", %{user: user} do
    # repo().one() raises Ecto.MultipleResultsError on a duplicate, so this is
    # the runtime crash the suffix prevents.
    create!(user, %{"title" => "Same Title"})
    create!(user, %{"title" => "Same Title"})

    assert PhoenixKitPosts.get_post_by_slug("same-title").slug == "same-title"
    assert PhoenixKitPosts.get_post_by_slug("same-title-2").slug == "same-title-2"
  end

  test "an explicit slug is still taken verbatim", %{user: user} do
    post = create!(user, %{"title" => "Anything", "slug" => "chosen-by-hand"})

    assert post.slug == "chosen-by-hand"
  end

  test "a post keeps its own slug rather than suffixing against itself", %{user: user} do
    post = create!(user, %{"title" => "Solo Post"})

    # Blanking asks for regeneration; the only row holding "solo-post" is this
    # one, so it must not be pushed to "solo-post-2".
    {:ok, updated} = PhoenixKitPosts.update_post(post, %{slug: ""})

    assert updated.slug == "solo-post"
  end

  test "regenerating still avoids a slug another post already holds", %{user: user} do
    create!(user, %{"title" => "Taken"})
    other = create!(user, %{"title" => "Something Else"})

    {:ok, updated} = PhoenixKitPosts.update_post(other, %{title: "Taken", slug: ""})

    assert updated.slug == "taken-2"
    assert Repo.get(Post, other.uuid).slug == "taken-2"
  end
end
