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
end
