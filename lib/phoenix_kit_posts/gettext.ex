defmodule PhoenixKitPosts.Gettext do
  @moduledoc """
  Gettext backend for the posts module's own translations.

  The module's admin LiveViews `use PhoenixKitWeb` (which binds the gettext
  macros to core's `PhoenixKitWeb.Gettext`) and then `use Gettext, backend:
  PhoenixKitPosts.Gettext` to rebind them to this backend, so the posts
  strings resolve against **this** package's catalogs (`priv/gettext`).
  Keeps the posts translations self-contained — extract + translate with the
  module's own `mix gettext.extract` / `mix gettext.merge`. Mirrors the
  sibling `PhoenixKitReferrals.Gettext` setup.
  """
  use Gettext.Backend, otp_app: :phoenix_kit_posts
end
