defmodule PhoenixKitPosts.SlugGenerationTest do
  @moduledoc """
  Slug generation goes through core, not a local ASCII-only pipeline.

  ## Why this asserts so little

  The obvious test — `assert slug("Видеопродакшн") == "videoprodakshn"` — is
  **version-dependent and merges red**. What core returns depends on which
  `phoenix_kit` this module resolves, and the lockfile here pins one that predates
  the `:transliterate` option entirely, so non-ASCII is stripped no matter what this
  module passes. phoenix_kit_dashboards#5 shipped exactly that mistake and had to be
  repaired after merge.

  So this pins only what holds at every core version. The non-ASCII cases start
  working on their own once core ships the locale-aware `Slug` **and** this module's
  floor moves to it — see the PR description for that ordering.
  """
  use ExUnit.Case, async: true

  alias PhoenixKitPosts.{Post, PostGroup, PostTag}

  defp post_slug(t), do: slug(Post.changeset(%Post{}, %{title: t, body: "x"}))
  defp tag_slug(t), do: slug(PostTag.changeset(%PostTag{}, %{name: t}))
  defp group_slug(t), do: slug(PostGroup.changeset(%PostGroup{}, %{name: t}))
  defp slug(cs), do: Ecto.Changeset.get_change(cs, :slug)

  test "ASCII slugs are unchanged across all three schemas" do
    assert post_slug("Hello World") == "hello-world"
    assert tag_slug("Corporate Video 2026") == "corporate-video-2026"
    assert group_slug("Product Updates") == "product-updates"
  end

  test "separators collapse and trim rather than doubling" do
    assert post_slug("  Hello   World  ") == "hello-world"
    refute String.starts_with?(post_slug("!! Hello"), "-")
    refute String.ends_with?(post_slug("Hello !!"), "-")
  end

  test "content-less input yields no slug rather than crashing" do
    assert post_slug("!!!") in [nil, ""]
    assert post_slug("") in [nil, ""]
  end

  describe "an existing slug survives being saved" do
    # These are all one bug: the generator asked `get_change(:slug)`, which is
    # nil both when the caller wants the slug left alone and when there is no
    # slug yet. So every save carrying no slug of its own re-derived one from
    # the title and moved a live URL, with nothing recording the old one.
    @live %Post{slug: "hand-picked", title: "Old Title"}

    test "a title edit keeps the hand-picked slug" do
      cs = Post.changeset(@live, %{title: "A Brand New Title"})

      refute Ecto.Changeset.changed?(cs, :slug)
    end

    test "the admin edit form keeps it, even though it re-sends the slug" do
      # web/edit.ex repopulates "slug" => post.slug, and cast/3 drops a value
      # equal to the data — so this arrives looking identical to no slug at
      # all, which is what carried the bug into ordinary edits.
      cs = Post.changeset(@live, %{"slug" => "hand-picked", "title" => "A Brand New Title"})

      refute Ecto.Changeset.changed?(cs, :slug)
    end

    test "publishing keeps it" do
      refute Ecto.Changeset.changed?(Post.changeset(@live, %{status: "public"}), :slug)
    end

    test "renaming a tag or group keeps theirs" do
      tag = PostTag.changeset(%PostTag{slug: "kept", name: "Old"}, %{name: "New"})
      group = PostGroup.changeset(%PostGroup{slug: "kept", name: "Old"}, %{name: "New"})

      refute Ecto.Changeset.changed?(tag, :slug)
      refute Ecto.Changeset.changed?(group, :slug)
    end
  end

  describe "generating one when there is not one" do
    test "a record whose slug is blank gets one from the title" do
      for blank <- [nil, ""] do
        cs = Post.changeset(%Post{slug: blank, title: "Old Title"}, %{title: "New Title"})

        assert Ecto.Changeset.get_change(cs, :slug) == "new-title"
      end
    end

    test "an explicit slug wins over the title" do
      cs = Post.changeset(@live, %{slug: "chosen-by-hand", title: "A Brand New Title"})

      assert Ecto.Changeset.get_change(cs, :slug) == "chosen-by-hand"
    end

    test "explicitly blanking one regenerates from the title" do
      # The column is NOT NULL, so a blank cannot simply be persisted.
      cs = Post.changeset(@live, %{slug: ""})

      assert Ecto.Changeset.get_change(cs, :slug) == "old-title"
    end
  end
end
