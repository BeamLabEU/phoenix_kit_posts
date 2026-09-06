defmodule PhoenixKitPosts.Integration.ScheduleInputFallbackTest do
  @moduledoc """
  `ScheduleInput.editor_tz/1`'s site fallback needs the settings table, so
  it lives in the integration tier; the pure conversions are in
  `test/schedule_input_test.exs`.
  """
  use PhoenixKitPosts.DataCase, async: false

  alias PhoenixKitPosts.Web.ScheduleInput

  test "no profile value — nil, blank, a map without the column, no user — is the site setting" do
    site = PhoenixKit.Settings.get_setting("time_zone", "0")
    assert ScheduleInput.editor_tz(%{user_timezone: nil}) == site
    assert ScheduleInput.editor_tz(%{user_timezone: ""}) == site
    assert ScheduleInput.editor_tz(%{uuid: "partial"}) == site
    assert ScheduleInput.editor_tz(nil) == site
  end
end

defmodule PhoenixKitPosts.Integration.ScheduledZoneTest do
  @moduledoc """
  A scheduled post carries the zone its schedule was typed in (core V185).
  """
  use PhoenixKitPosts.DataCase, async: false

  alias PhoenixKitPosts.Post

  test "the zone is cast, bounded and stored next to scheduled_at" do
    user = user_fixture()

    {:ok, post} =
      PhoenixKitPosts.create_post(user.uuid, %{
        "title" => "Scheduled",
        "content" => "…",
        "type" => "post",
        "status" => "draft",
        "scheduled_at" => ~U[2026-07-15 07:00:00Z],
        "time_zone" => "Europe/Tallinn"
      })

    assert Repo.get!(Post, post.uuid).time_zone == "Europe/Tallinn"

    changeset = Post.changeset(%Post{}, %{"time_zone" => "bogus"})
    assert {"is not a timezone", _} = changeset.errors[:time_zone]

    for ok <- ["Europe/Tallinn", "2", "5.5", "0"] do
      refute Post.changeset(%Post{}, %{"time_zone" => ok}).errors[:time_zone], ok
    end
  end
end
