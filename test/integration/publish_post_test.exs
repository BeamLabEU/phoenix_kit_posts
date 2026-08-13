defmodule PhoenixKitPosts.Integration.PublishPostTest do
  use PhoenixKitPosts.DataCase, async: true

  alias PhoenixKitPosts.Post

  setup do
    %{user: user_fixture()}
  end

  describe "publish_post/2" do
    test "publishing twice from the same stale struct logs once", %{user: user} do
      # The whole bug, and it needs no concurrency to show: the old guard read
      # `post.status` off the struct in hand, so a second caller holding the
      # same pre-publish copy believed it had made the transition too.
      post = post_fixture(user, status: "scheduled")

      assert {:ok, _} = PhoenixKitPosts.publish_post(post)
      assert {:ok, _} = PhoenixKitPosts.publish_post(post)

      assert_activity_count("post.published", post.uuid, 1)
    end

    test "the loser is told the post is public, not handed its own stale copy", %{user: user} do
      post = post_fixture(user, status: "scheduled")

      {:ok, _} = PhoenixKitPosts.publish_post(post)
      {:ok, current} = PhoenixKitPosts.publish_post(post)

      # The handler logs this status. Echoing the caller's struct would print
      # "scheduled" for a post that is public.
      assert current.status == "public"
    end

    test "an already-public post logs nothing and stays published", %{user: user} do
      post = post_fixture(user, status: "public")

      assert {:ok, current} = PhoenixKitPosts.publish_post(post)

      assert current.status == "public"
      assert_activity_count("post.published", post.uuid, 0)
    end

    test "a draft publishes by default — the admin Publish button", %{user: user} do
      # The default has to be wide. Narrowing it to "scheduled" would make the
      # admin action return {:ok, _} and flash success over an unpublished post.
      post = post_fixture(user, status: "draft")

      assert {:ok, published} = PhoenixKitPosts.publish_post(post)

      assert published.status == "public"
      assert_activity_count("post.published", post.uuid, 1)
    end

    test "only_if refuses a transition from outside the given statuses", %{user: user} do
      post = post_fixture(user, status: "draft")

      assert {:ok, current} = PhoenixKitPosts.publish_post(post, only_if: ["scheduled"])

      assert current.status == "draft"
      assert_activity_count("post.published", post.uuid, 0)
    end

    test "a deleted post reports not_found rather than succeeding", %{user: user} do
      post = post_fixture(user, status: "scheduled")
      Repo.delete!(post)

      assert {:error, :not_found} = PhoenixKitPosts.publish_post(post)
    end

    test "publishing leaves the slug alone", %{user: user} do
      post = post_fixture(user, status: "scheduled", slug: "hand-picked", title: "Some Title")

      {:ok, published} = PhoenixKitPosts.publish_post(post)

      assert published.slug == "hand-picked"
    end
  end

  describe "process_scheduled_posts/0" do
    test "publishes what is due and counts only what it published", %{user: user} do
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      due = post_fixture(user, status: "scheduled", scheduled_at: past)
      already = post_fixture(user, status: "scheduled", scheduled_at: past)

      # Someone else got to this one first — a second sweep, or the core
      # catch-up worker running the same function.
      {:ok, _} = PhoenixKitPosts.publish_post(already)

      assert {:ok, 1} = PhoenixKitPosts.process_scheduled_posts()

      assert Repo.get(Post, due.uuid).status == "public"
      assert_activity_count("post.published", due.uuid, 1)
      assert_activity_count("post.published", already.uuid, 1)
    end

    test "leaves a post scheduled for the future alone", %{user: user} do
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      post = post_fixture(user, status: "scheduled", scheduled_at: future)

      assert {:ok, 0} = PhoenixKitPosts.process_scheduled_posts()
      assert Repo.get(Post, post.uuid).status == "scheduled"
    end

    test "running twice publishes once", %{user: user} do
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      post = post_fixture(user, status: "scheduled", scheduled_at: past)

      assert {:ok, 1} = PhoenixKitPosts.process_scheduled_posts()
      assert {:ok, 0} = PhoenixKitPosts.process_scheduled_posts()

      assert_activity_count("post.published", post.uuid, 1)
    end
  end
end
