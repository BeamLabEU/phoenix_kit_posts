defmodule PhoenixKitPosts.Web.Settings do
  @moduledoc """
  LiveView for posts module configuration and settings management.

  This module provides a comprehensive interface for managing all aspects
  of the PhoenixKit posts system, including:

  - **Content Limits**: Configure max media, title length, subtitle, content, mentions, tags
  - **Module Configuration**: Enable/disable module, set pagination, default status
  - **Feature Toggles**: Control comments, likes, scheduling, groups, reposts, SEO
  - **Moderation**: Configure post approval and comment moderation

  ## Route

  This LiveView is mounted at `{prefix}/admin/settings/posts` and requires
  appropriate admin permissions.

  Note: `{prefix}` is your configured PhoenixKit URL prefix (default: `/phoenix_kit`).

  ## Features

  - Real-time settings updates with immediate effect
  - Input validation with user-friendly error messages
  - Preview of limits and examples
  - Organized by category for easy navigation

  ## Permissions

  Access is restricted to users with admin or owner roles in PhoenixKit.
  """

  use PhoenixKitWeb, :live_view
  # Rebind gettext macros to the posts module's own catalogs (priv/gettext).
  use Gettext, backend: PhoenixKitPosts.Gettext

  alias PhoenixKit.Settings

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, gettext("Posts Settings"))
      |> assign(:page_subtitle, gettext("Configure posts module behavior, limits, and features"))
      |> assign(:project_title, Settings.get_project_title())
      |> assign(:saving, false)

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load_settings(socket)}
  end

  def handle_event("save", params, socket) do
    socket = assign(socket, :saving, true)

    # Extract settings from params
    settings = Map.get(params, "settings", %{})

    # Update all settings
    results =
      Enum.map(settings, fn {key, value} ->
        Settings.update_setting(key, value)
      end)

    # Check if all updates succeeded
    socket =
      if Enum.all?(results, fn
           {:ok, _} -> true
           _ -> false
         end) do
        socket
        |> put_flash(:info, gettext("Settings saved successfully"))
        |> load_settings()
      else
        put_flash(socket, :error, gettext("Failed to save some settings"))
      end

    {:noreply, assign(socket, :saving, false)}
  end

  def handle_event("reset_defaults", _params, socket) do
    # Reset all settings to defaults
    defaults = %{
      # Content Limits
      "posts_max_media" => "10",
      "posts_max_title_length" => "255",
      "posts_max_subtitle_length" => "500",
      "posts_max_content_length" => "50000",
      "posts_max_mentions" => "10",
      "posts_max_tags" => "20",
      # Module Configuration
      "posts_enabled" => "true",
      "posts_per_page" => "20",
      "posts_default_status" => "draft",
      # Feature Toggles
      "posts_likes_enabled" => "true",
      "posts_allow_scheduling" => "true",
      "posts_allow_groups" => "true",
      "posts_allow_reposts" => "true",
      "posts_seo_auto_slug" => "true",
      "posts_show_view_count" => "true",
      # Moderation
      "posts_require_approval" => "false"
    }

    Enum.each(defaults, fn {key, value} ->
      Settings.update_setting(key, value)
    end)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Settings reset to defaults"))
     |> load_settings()}
  end

  defp load_settings(socket) do
    socket
    # Content Limits
    |> assign(:posts_max_media, Settings.get_setting("posts_max_media", "10"))
    |> assign(:posts_max_title_length, Settings.get_setting("posts_max_title_length", "255"))
    |> assign(
      :posts_max_subtitle_length,
      Settings.get_setting("posts_max_subtitle_length", "500")
    )
    |> assign(
      :posts_max_content_length,
      Settings.get_setting("posts_max_content_length", "50000")
    )
    |> assign(:posts_max_mentions, Settings.get_setting("posts_max_mentions", "10"))
    |> assign(:posts_max_tags, Settings.get_setting("posts_max_tags", "20"))
    # Module Configuration
    |> assign(:posts_enabled, Settings.get_setting("posts_enabled", "true"))
    |> assign(:posts_per_page, Settings.get_setting("posts_per_page", "20"))
    |> assign(:posts_default_status, Settings.get_setting("posts_default_status", "draft"))
    # Feature Toggles
    |> assign(:posts_likes_enabled, Settings.get_setting("posts_likes_enabled", "true"))
    |> assign(
      :posts_allow_scheduling,
      Settings.get_setting("posts_allow_scheduling", "true")
    )
    |> assign(:posts_allow_groups, Settings.get_setting("posts_allow_groups", "true"))
    |> assign(:posts_allow_reposts, Settings.get_setting("posts_allow_reposts", "true"))
    |> assign(:posts_seo_auto_slug, Settings.get_setting("posts_seo_auto_slug", "true"))
    |> assign(:posts_show_view_count, Settings.get_setting("posts_show_view_count", "true"))
    # Moderation
    |> assign(:posts_require_approval, Settings.get_setting("posts_require_approval", "false"))
  end

  @doc """
  Lightweight in-card section heading (icon + title + rule). Local copy of
  core's `Core.FormSection.section_header/1` under a distinct name, so this
  package renders identically without requiring a core release that exports
  it (and won't conflict with the core import once it does).
  """
  attr(:icon, :string, required: true)
  attr(:title, :string, required: true)
  attr(:class, :string, default: nil)

  def settings_section_header(assigns) do
    ~H"""
    <div class={["flex items-center gap-2 pt-4 first:pt-0", @class]}>
      <.icon name={@icon} class="w-4 h-4 text-primary/70" />
      <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
        {@title}
      </h3>
      <div class="flex-1 border-t border-base-300 ml-2"></div>
    </div>
    """
  end
end
