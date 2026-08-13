defmodule PhoenixKitPosts.Integration.HarnessTest do
  @moduledoc """
  Proves the harness is wired before anything relies on it.

  Every context function in this module rescues its own database errors and
  returns a plausible nothing, so a misconfigured suite does not fail — it
  passes while asserting the rescue. These tests are the loud failure that
  would otherwise be missing.
  """
  use PhoenixKitPosts.DataCase, async: true

  test "core resolves the test repo, not some other one" do
    # Without `config :phoenix_kit, repo: ...` this returns nil or raises, and
    # every context call quietly becomes a no-op.
    assert PhoenixKit.RepoHelper.repo() == PhoenixKitPosts.Test.Repo
  end

  test "the posts tables exist and round-trip" do
    user = user_fixture()
    post = post_fixture(user, title: "Round Trip", slug: "round-trip")

    assert PhoenixKitPosts.get_post(post.uuid).title == "Round Trip"
  end

  test "the activity table is reachable and the counter counts" do
    user = user_fixture()
    post = post_fixture(user)

    assert_activity_count("post.published", post.uuid, 0)
  end
end
