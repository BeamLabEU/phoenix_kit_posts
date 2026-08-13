defmodule PhoenixKitPosts.DataCase do
  @moduledoc """
  Test case for tests that hit the database.

  Until this existed, `config/test.exs` configured no repo at all, so nothing
  in the context layer could be exercised — `publish_post/2` and
  `process_scheduled_posts/0` among them, which is how a double-publish
  survived in the module unnoticed.

  Tests using this case are tagged `:integration` and are excluded
  automatically when PostgreSQL is unavailable, so `mix test` still runs the
  unit half on a machine with no database.

      defmodule PhoenixKitPosts.Integration.SomethingTest do
        use PhoenixKitPosts.DataCase, async: true
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import PhoenixKitPosts.DataCase

      alias PhoenixKitPosts.Test.Repo
    end
  end

  # The `import` in `using/1` applies to the test modules, not to this one.
  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitPosts.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc """
  A persisted user, for posts that need a real author.

  `phoenix_kit_posts.user_uuid` is NOT NULL behind `fk_posts_user_uuid`, so a
  generated uuid will not do.
  """
  def user_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    # Inserted directly rather than through `register_user/2`: registration
    # runs the rate limiter, whose ETS backend is not started in this suite,
    # and none of these tests are about registration.
    %PhoenixKit.Users.Auth.User{}
    |> Ecto.Changeset.change(
      Map.merge(
        %{
          email: "author-#{n}@example.com",
          hashed_password: Bcrypt.hash_pwd_salt("ValidPassword123!"),
          confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          is_active: true
        },
        attrs
      )
    )
    |> TestRepo.insert!()
  end

  @doc """
  A persisted post, defaulting to a draft.

  Inserted directly so a test can set a status the public API would not let it
  reach, and so `scheduled_at` can be in the past — which `Post.changeset/2`
  refuses, and which is exactly the state the sweep exists to handle.
  """
  def post_fixture(user, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      title: "Post #{n}",
      slug: "post-#{n}",
      content: "Body #{n}",
      status: "draft",
      user_uuid: user.uuid
    }

    %PhoenixKitPosts.Post{}
    |> Ecto.Changeset.change(Map.merge(defaults, Map.new(attrs)))
    |> TestRepo.insert!()
  end

  @doc """
  Asserts an activity was logged exactly `count` times for `resource_uuid`.

  Counting is the point. `Activity.log/1` rescues its own errors and
  `log_post_activity/4` rescues again, so a wholly broken activity pipeline
  writes nothing and quietly satisfies any "no duplicate" assertion phrased as
  a refute — which is the failure this helper exists to make impossible.
  """
  def assert_activity_count(action, resource_uuid, count) do
    actual =
      TestRepo.aggregate(
        from(a in "phoenix_kit_activities",
          where: a.action == ^action,
          where: a.resource_uuid == type(^resource_uuid, Ecto.UUID)
        ),
        :count
      )

    ExUnit.Assertions.assert(
      actual == count,
      "expected #{count} #{action} activity row(s) for #{resource_uuid}, found #{actual}"
    )
  end
end
