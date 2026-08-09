defmodule PhoenixKitPosts.SlugGenerationTest do
  @moduledoc """
  Slug generation goes through core (and therefore `locale_slug`), not a local
  ASCII-only pipeline.

  The pipeline this replaced deleted every non-ASCII character, so a Cyrillic or
  Greek title produced an EMPTY slug — and an empty slug is worse than a wrong
  one, because callers read it as "no slug yet" and regenerate on every save.

  These are the assertions that would fail if the change were reverted.
  """
  use ExUnit.Case, async: true

  alias PhoenixKitPosts.{Post, PostGroup, PostTag}

  defp post_slug(t), do: slug(Post.changeset(%Post{}, %{title: t, body: "x"}))
  defp tag_slug(t), do: slug(PostTag.changeset(%PostTag{}, %{name: t}))
  defp group_slug(t), do: slug(PostGroup.changeset(%PostGroup{}, %{name: t}))
  defp slug(cs), do: Ecto.Changeset.get_change(cs, :slug)

  test "a Cyrillic title yields a real slug, not an empty one" do
    assert post_slug("Видеопродакшн") == "videoprodakshn"
    assert tag_slug("Видеопродакшн") == "videoprodakshn"
    assert group_slug("Видеопродакшн") == "videoprodakshn"
  end

  test "a Greek title yields a real slug" do
    assert post_slug("Καλημέρα") == "kalimera"
  end

  test "German keeps its letters instead of dropping them" do
    # The old pipeline gave "gre-fuball": ö decomposed and ß was deleted.
    assert post_slug("Größe Fußball") == "grosse-fussball"
  end

  test "plain ASCII is unchanged" do
    assert post_slug("Hello World") == "hello-world"
  end

  test "content-less input still yields no slug rather than crashing" do
    assert post_slug("!!!") in [nil, ""]
  end
end
