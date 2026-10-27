defmodule PhoenixKitPosts.MigrationsTest do
  use ExUnit.Case, async: true

  alias PhoenixKitPosts.Migrations

  @moduledoc """
  Pins the ownership design for `phoenix_kit_posts`: this package owns all 13
  `phoenix_kit_post*`/`phoenix_kit_comment_*` tables' FUTURE shape through its
  module migration chain, while core's V135/V167/V168/V185 baseline still
  creates every table on every install, and the chain's V1 merely ADOPTS
  that shape (stamps the `pkpo_schema:` marker on the anchor table,
  `phoenix_kit_posts`, changes no shape).

  Every test here is a pure data/string assertion over
  `up_statements/2`/`down_statements/2`/`up/1`/`down/1`-as-source-text and
  core's static `PhoenixKit.Migrations.ExpectedSchema.objects/1` manifest —
  none of them touch a database.
  """

  test "PhoenixKitPosts declares the module-owned migration chain" do
    # Assert the VALUE, not `function_exported?/3` — `use PhoenixKit.Module`
    # injects an overridable default `migration_module/0`, so exportedness
    # says nothing about whether this module declares one.
    assert Code.ensure_loaded?(PhoenixKitPosts)

    assert PhoenixKitPosts.migration_module() == Migrations,
           """
           PhoenixKitPosts no longer declares its migration chain \
           (migration_module/0 returned #{inspect(PhoenixKitPosts.migration_module())}).

           The chain is how phoenix_kit_posts' future shape is versioned
           (pkpo_schema marker) and how `mix phoenix_kit.update` migrates hosts.
           """
  end

  describe "the coordinator implements the protocol" do
    alias PhoenixKit.Migrations.Postgres.Helpers

    test "current_version/0 and version_table/0" do
      assert Migrations.current_version() == 1
      assert Migrations.version_table() == "phoenix_kit_posts"
    end

    test "initial_version/0" do
      assert Migrations.initial_version() == 1
    end

    # `mix phoenix_kit_hello_world.audit_migrations` (the canonical auditor
    # for this protocol) refuses to drive a coordinator missing any of these
    # five — `mix phoenix_kit.update` itself only calls
    # `migrated_version_runtime/1` + `current_version/0`, but `up/1` needs
    # `migrated_version/1` to re-read the version it is about to change.
    test "exports the full five-function protocol, plus version_table/0 and initial_version/0" do
      for {fun, arity} <- [
            {:current_version, 0},
            {:up, 1},
            {:down, 1},
            {:migrated_version, 1},
            {:migrated_version_runtime, 1},
            {:version_table, 0},
            {:initial_version, 0}
          ] do
        assert function_exported?(Migrations, fun, arity),
               "#{inspect(Migrations)} does not export #{fun}/#{arity}"
      end
    end

    # The marker decides whether any LATER version ever runs: core's
    # `classify/2` reads it and answers `:up_to_date` for every version at or
    # below it. Stamping a version this chain does not have therefore skips
    # V2 and everything after it, silently and permanently.
    test "refuses to stamp a version this chain does not have" do
      too_high = Migrations.current_version() + 1

      assert_raise ArgumentError, ~r/has no version #{too_high}/, fn ->
        Migrations.up_statements("public", too_high)
      end

      assert_raise ArgumentError, ~r/has no version #{too_high}/, fn ->
        Migrations.down_statements("public", too_high)
      end

      # The ceiling itself stays reachable, or the guard would just break
      # the chain instead of bounding it.
      assert Migrations.up_statements("public", Migrations.current_version()) != []
    end

    # This chain interpolates the prefix into every object it creates, and
    # Postgres TRUNCATES an identifier past 63 bytes silently rather than
    # rejecting it — so a prefix core would refuse yields object names that
    # differ from core's while every command still exits 0, breaking the
    # contract adoption rests on. The rules are therefore core's, and this
    # test compares against core rather than restating them.
    test "every public builder that emits SQL validates its own prefix" do
      for fun <- [:up_statements, :down_statements] do
        assert_raise ArgumentError, fn -> apply(Migrations, fun, ["EVIL\";DROP"]) end
        assert_raise ArgumentError, fn -> apply(Migrations, fun, [String.duplicate("a", 30)]) end
        assert_raise ArgumentError, fn -> apply(Migrations, fun, [123]) end
      end
    end

    test "the prefix rules are core's, case and length included" do
      for prefix <- [
            "public",
            "posts_alt",
            "Posts",
            "9leading_digit",
            "has-dash",
            String.duplicate("a", 20),
            String.duplicate("a", 21),
            String.duplicate("a", 30)
          ] do
        core_accepts =
          try do
            Helpers.validate_prefix!(prefix)
            true
          rescue
            ArgumentError -> false
          end

        ours_accepts =
          try do
            Migrations.up_statements(prefix)
            true
          rescue
            ArgumentError -> false
          end

        assert ours_accepts == core_accepts,
               "prefix #{inspect(prefix)}: core #{if core_accepts, do: "accepts", else: "rejects"}, " <>
                 "this chain #{if ours_accepts, do: "accepts", else: "rejects"} — the two must agree, " <>
                 "or the object names this chain creates stop matching core's"
      end
    end

    test "rejects a prefix that cannot be safely interpolated into DDL" do
      for bad <- ["public.\"; DROP TABLE x; --", "1st", "a-b", ""] do
        assert_raise ArgumentError, fn -> Migrations.up_statements(bad) end
        assert_raise ArgumentError, fn -> Migrations.down_statements(bad, 0) end
      end
    end
  end

  describe "the chain's per-version statement content is pinned (drift guard)" do
    # V1 is a PUBLISHED version once this ships. A host that has already run
    # it will never run it again, so editing its content does not "fix" that
    # host — it silently splits fresh installs from existing ones. Pinning
    # the exact normalised text makes that split a deliberate, visible diff
    # instead of an accidental one buried in a refactor.
    defp normalised(statements),
      do: Enum.map(statements, &(&1 |> String.replace(~r/\s+/, " ") |> String.trim()))

    test "V1's published statements are frozen" do
      v1 = Migrations.up_statements("public", 1) |> normalised()

      assert v1 == [
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_posts ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"title\" character varying(255) NOT NULL, \"sub_title\" character varying(255), \"content\" text NOT NULL, \"type\" character varying(255) DEFAULT 'post'::character varying NOT NULL, \"status\" character varying(255) DEFAULT 'draft'::character varying NOT NULL, \"scheduled_at\" timestamp with time zone, \"published_at\" timestamp with time zone, \"repost_url\" character varying(255), \"slug\" character varying(255) NOT NULL, \"like_count\" integer DEFAULT 0 NOT NULL, \"comment_count\" integer DEFAULT 0 NOT NULL, \"view_count\" integer DEFAULT 0 NOT NULL, \"metadata\" jsonb DEFAULT '{}'::jsonb, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"dislike_count\" integer DEFAULT 0 NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_comments ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"post_uuid\" uuid NOT NULL, \"parent_uuid\" uuid, \"content\" text NOT NULL, \"status\" character varying(255) DEFAULT 'published'::character varying NOT NULL, \"depth\" integer DEFAULT 0 NOT NULL, \"like_count\" integer DEFAULT 0 NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"dislike_count\" integer DEFAULT 0 NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_likes ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"post_uuid\" uuid NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_dislikes ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"post_uuid\" uuid NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_tags ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"name\" character varying(255) NOT NULL, \"slug\" character varying(255) NOT NULL, \"usage_count\" integer DEFAULT 0 NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_tag_assignments ( \"post_uuid\" uuid NOT NULL, \"tag_uuid\" uuid NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_groups ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"name\" character varying(255) NOT NULL, \"slug\" character varying(255) NOT NULL, \"description\" text, \"cover_image_uuid\" uuid, \"post_count\" integer DEFAULT 0 NOT NULL, \"is_public\" boolean DEFAULT false NOT NULL, \"position\" integer DEFAULT 0 NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_group_assignments ( \"post_uuid\" uuid NOT NULL, \"group_uuid\" uuid NOT NULL, \"position\" integer DEFAULT 0 NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_media ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"post_uuid\" uuid NOT NULL, \"file_uuid\" uuid NOT NULL, \"position\" integer NOT NULL, \"caption\" text, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_mentions ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"post_uuid\" uuid NOT NULL, \"mention_type\" character varying(255) DEFAULT 'mention'::character varying NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_post_views ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"post_uuid\" uuid NOT NULL, \"ip_address\" character varying(255), \"user_agent_hash\" character varying(255), \"session_id\" character varying(255), \"viewed_at\" timestamp with time zone NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_comment_likes ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"comment_uuid\" uuid NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_comment_dislikes ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"comment_uuid\" uuid NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "ALTER TABLE public.phoenix_kit_posts ADD COLUMN IF NOT EXISTS \"time_zone\" character varying(64)",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_posts_pkey' AND t.relname = 'phoenix_kit_posts' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_posts ADD CONSTRAINT phoenix_kit_posts_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_comments_pkey' AND t.relname = 'phoenix_kit_post_comments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_comments ADD CONSTRAINT phoenix_kit_post_comments_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_likes_pkey' AND t.relname = 'phoenix_kit_post_likes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_likes ADD CONSTRAINT phoenix_kit_post_likes_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_dislikes_pkey' AND t.relname = 'phoenix_kit_post_dislikes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_dislikes ADD CONSTRAINT phoenix_kit_post_dislikes_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_tags_pkey' AND t.relname = 'phoenix_kit_post_tags' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_tags ADD CONSTRAINT phoenix_kit_post_tags_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_groups_pkey' AND t.relname = 'phoenix_kit_post_groups' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_groups ADD CONSTRAINT phoenix_kit_post_groups_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_media_pkey' AND t.relname = 'phoenix_kit_post_media' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_media ADD CONSTRAINT phoenix_kit_post_media_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_mentions_pkey' AND t.relname = 'phoenix_kit_post_mentions' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_mentions ADD CONSTRAINT phoenix_kit_post_mentions_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_views_pkey' AND t.relname = 'phoenix_kit_post_views' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_views ADD CONSTRAINT phoenix_kit_post_views_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_comment_likes_pkey' AND t.relname = 'phoenix_kit_comment_likes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_comment_likes ADD CONSTRAINT phoenix_kit_comment_likes_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_comment_dislikes_pkey' AND t.relname = 'phoenix_kit_comment_dislikes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_comment_dislikes ADD CONSTRAINT phoenix_kit_comment_dislikes_pkey PRIMARY KEY (uuid); END IF; END $$",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_posts_published_at_index ON public.phoenix_kit_posts USING btree (published_at)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_posts_scheduled_at_index ON public.phoenix_kit_posts USING btree (scheduled_at)",
               "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_posts_slug_index ON public.phoenix_kit_posts USING btree (slug)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_posts_status_index ON public.phoenix_kit_posts USING btree (status)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_posts_status_published_at_index ON public.phoenix_kit_posts USING btree (status, published_at)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_posts_type_index ON public.phoenix_kit_posts USING btree (type)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_posts_type_status_index ON public.phoenix_kit_posts USING btree (type, status)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_posts_user_uuid_idx ON public.phoenix_kit_posts USING btree (user_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_comments_depth_index ON public.phoenix_kit_post_comments USING btree (depth)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_comments_parent_id_index ON public.phoenix_kit_post_comments USING btree (parent_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_comments_post_id_index ON public.phoenix_kit_post_comments USING btree (post_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_comments_post_id_parent_id_depth_index ON public.phoenix_kit_post_comments USING btree (post_uuid, parent_uuid, depth)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_comments_status_index ON public.phoenix_kit_post_comments USING btree (status)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_comments_user_uuid_idx ON public.phoenix_kit_post_comments USING btree (user_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_likes_post_id_index ON public.phoenix_kit_post_likes USING btree (post_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_likes_user_uuid_idx ON public.phoenix_kit_post_likes USING btree (user_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_dislikes_post_id_index ON public.phoenix_kit_post_dislikes USING btree (post_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_dislikes_user_uuid_idx ON public.phoenix_kit_post_dislikes USING btree (user_uuid)",
               "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_post_tags_slug_index ON public.phoenix_kit_post_tags USING btree (slug)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_tags_usage_count_index ON public.phoenix_kit_post_tags USING btree (usage_count)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_tag_assignments_post_id_index ON public.phoenix_kit_post_tag_assignments USING btree (post_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_tag_assignments_tag_id_index ON public.phoenix_kit_post_tag_assignments USING btree (tag_uuid)",
               "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_post_tag_assignments_post_uuid_tag_uuid_index ON public.phoenix_kit_post_tag_assignments USING btree (post_uuid, tag_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_groups_is_public_index ON public.phoenix_kit_post_groups USING btree (is_public)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_groups_position_index ON public.phoenix_kit_post_groups USING btree (\"position\")",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_groups_user_uuid_idx ON public.phoenix_kit_post_groups USING btree (user_uuid)",
               "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_post_groups_user_uuid_slug_index ON public.phoenix_kit_post_groups USING btree (user_uuid, slug)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_group_assignments_group_id_index ON public.phoenix_kit_post_group_assignments USING btree (group_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_group_assignments_group_id_position_index ON public.phoenix_kit_post_group_assignments USING btree (group_uuid, \"position\")",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_group_assignments_position_index ON public.phoenix_kit_post_group_assignments USING btree (\"position\")",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_group_assignments_post_id_index ON public.phoenix_kit_post_group_assignments USING btree (post_uuid)",
               "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_post_group_assignments_post_uuid_group_uuid_index ON public.phoenix_kit_post_group_assignments USING btree (post_uuid, group_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_media_file_id_index ON public.phoenix_kit_post_media USING btree (file_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_media_position_index ON public.phoenix_kit_post_media USING btree (\"position\")",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_media_post_id_index ON public.phoenix_kit_post_media USING btree (post_uuid)",
               "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_post_media_post_uuid_position_index ON public.phoenix_kit_post_media USING btree (post_uuid, \"position\")",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_mentions_mention_type_index ON public.phoenix_kit_post_mentions USING btree (mention_type)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_mentions_post_id_index ON public.phoenix_kit_post_mentions USING btree (post_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_mentions_user_uuid_idx ON public.phoenix_kit_post_mentions USING btree (user_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_views_post_id_index ON public.phoenix_kit_post_views USING btree (post_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_views_post_id_viewed_at_index ON public.phoenix_kit_post_views USING btree (post_uuid, viewed_at)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_views_session_id_index ON public.phoenix_kit_post_views USING btree (session_id)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_views_viewed_at_index ON public.phoenix_kit_post_views USING btree (viewed_at)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_post_views_user_uuid_idx ON public.phoenix_kit_post_views USING btree (user_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_comment_likes_comment_id_index ON public.phoenix_kit_comment_likes USING btree (comment_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_comment_likes_user_uuid_idx ON public.phoenix_kit_comment_likes USING btree (user_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_comment_dislikes_comment_id_index ON public.phoenix_kit_comment_dislikes USING btree (comment_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_comment_dislikes_user_uuid_idx ON public.phoenix_kit_comment_dislikes USING btree (user_uuid)",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_posts_user_uuid' AND t.relname = 'phoenix_kit_posts' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_posts ADD CONSTRAINT fk_posts_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_comments_parent_id_fkey' AND t.relname = 'phoenix_kit_post_comments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_comments ADD CONSTRAINT phoenix_kit_post_comments_parent_id_fkey FOREIGN KEY (parent_uuid) REFERENCES public.phoenix_kit_post_comments(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_comments_post_id_fkey' AND t.relname = 'phoenix_kit_post_comments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_comments ADD CONSTRAINT phoenix_kit_post_comments_post_id_fkey FOREIGN KEY (post_uuid) REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_post_comments_user_uuid' AND t.relname = 'phoenix_kit_post_comments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_comments ADD CONSTRAINT fk_post_comments_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_likes_post_id_fkey' AND t.relname = 'phoenix_kit_post_likes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_likes ADD CONSTRAINT phoenix_kit_post_likes_post_id_fkey FOREIGN KEY (post_uuid) REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_post_likes_user_uuid' AND t.relname = 'phoenix_kit_post_likes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_likes ADD CONSTRAINT fk_post_likes_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_dislikes_post_id_fkey' AND t.relname = 'phoenix_kit_post_dislikes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_dislikes ADD CONSTRAINT phoenix_kit_post_dislikes_post_id_fkey FOREIGN KEY (post_uuid) REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_post_dislikes_user_uuid' AND t.relname = 'phoenix_kit_post_dislikes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_dislikes ADD CONSTRAINT fk_post_dislikes_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_tag_assignments_post_id_fkey' AND t.relname = 'phoenix_kit_post_tag_assignments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_tag_assignments ADD CONSTRAINT phoenix_kit_post_tag_assignments_post_id_fkey FOREIGN KEY (post_uuid) REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_tag_assignments_tag_id_fkey' AND t.relname = 'phoenix_kit_post_tag_assignments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_tag_assignments ADD CONSTRAINT phoenix_kit_post_tag_assignments_tag_id_fkey FOREIGN KEY (tag_uuid) REFERENCES public.phoenix_kit_post_tags(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_groups_cover_image_id_fkey' AND t.relname = 'phoenix_kit_post_groups' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_groups ADD CONSTRAINT phoenix_kit_post_groups_cover_image_id_fkey FOREIGN KEY (cover_image_uuid) REFERENCES public.phoenix_kit_files(uuid) ON DELETE SET NULL; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_post_groups_user_uuid' AND t.relname = 'phoenix_kit_post_groups' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_groups ADD CONSTRAINT fk_post_groups_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_group_assignments_group_id_fkey' AND t.relname = 'phoenix_kit_post_group_assignments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_group_assignments ADD CONSTRAINT phoenix_kit_post_group_assignments_group_id_fkey FOREIGN KEY (group_uuid) REFERENCES public.phoenix_kit_post_groups(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_group_assignments_post_id_fkey' AND t.relname = 'phoenix_kit_post_group_assignments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_group_assignments ADD CONSTRAINT phoenix_kit_post_group_assignments_post_id_fkey FOREIGN KEY (post_uuid) REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_media_file_id_fkey' AND t.relname = 'phoenix_kit_post_media' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_media ADD CONSTRAINT phoenix_kit_post_media_file_id_fkey FOREIGN KEY (file_uuid) REFERENCES public.phoenix_kit_files(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_media_post_id_fkey' AND t.relname = 'phoenix_kit_post_media' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_media ADD CONSTRAINT phoenix_kit_post_media_post_id_fkey FOREIGN KEY (post_uuid) REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_mentions_post_id_fkey' AND t.relname = 'phoenix_kit_post_mentions' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_mentions ADD CONSTRAINT phoenix_kit_post_mentions_post_id_fkey FOREIGN KEY (post_uuid) REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_post_mentions_user_uuid' AND t.relname = 'phoenix_kit_post_mentions' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_mentions ADD CONSTRAINT fk_post_mentions_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_post_views_post_id_fkey' AND t.relname = 'phoenix_kit_post_views' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_views ADD CONSTRAINT phoenix_kit_post_views_post_id_fkey FOREIGN KEY (post_uuid) REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_post_views_user_uuid' AND t.relname = 'phoenix_kit_post_views' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_post_views ADD CONSTRAINT fk_post_views_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_comment_likes_comment_id_fkey' AND t.relname = 'phoenix_kit_comment_likes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_comment_likes ADD CONSTRAINT phoenix_kit_comment_likes_comment_id_fkey FOREIGN KEY (comment_uuid) REFERENCES public.phoenix_kit_post_comments(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_comment_likes_user_uuid' AND t.relname = 'phoenix_kit_comment_likes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_comment_likes ADD CONSTRAINT fk_comment_likes_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_comment_dislikes_comment_id_fkey' AND t.relname = 'phoenix_kit_comment_dislikes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_comment_dislikes ADD CONSTRAINT phoenix_kit_comment_dislikes_comment_id_fkey FOREIGN KEY (comment_uuid) REFERENCES public.phoenix_kit_post_comments(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_comment_dislikes_user_uuid' AND t.relname = 'phoenix_kit_comment_dislikes' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_comment_dislikes ADD CONSTRAINT fk_comment_dislikes_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "COMMENT ON TABLE public.phoenix_kit_posts IS 'pkpo_schema:1'"
             ]
    end
  end

  describe "the chain DDL adopts core's V135/V168/V185 shape" do
    test "V1 uses core's exact object names (shape-identical adoption)" do
      statements = Enum.join(Migrations.up_statements(), "\n")

      for name <- [
            "phoenix_kit_posts_pkey",
            "phoenix_kit_post_comments_pkey",
            "phoenix_kit_post_likes_pkey",
            "phoenix_kit_post_dislikes_pkey",
            "phoenix_kit_post_tags_pkey",
            "phoenix_kit_post_groups_pkey",
            "phoenix_kit_post_media_pkey",
            "phoenix_kit_post_mentions_pkey",
            "phoenix_kit_post_views_pkey",
            "phoenix_kit_comment_likes_pkey",
            "phoenix_kit_comment_dislikes_pkey",
            "phoenix_kit_posts_slug_index",
            "phoenix_kit_post_tags_slug_index",
            "phoenix_kit_post_tag_assignments_post_uuid_tag_uuid_index",
            "phoenix_kit_post_groups_user_uuid_slug_index",
            "phoenix_kit_post_group_assignments_post_uuid_group_uuid_index",
            "phoenix_kit_post_media_post_uuid_position_index",
            "fk_posts_user_uuid",
            "phoenix_kit_post_comments_parent_id_fkey",
            "phoenix_kit_post_comments_post_id_fkey",
            "fk_post_comments_user_uuid",
            "phoenix_kit_post_likes_post_id_fkey",
            "fk_post_likes_user_uuid",
            "phoenix_kit_post_dislikes_post_id_fkey",
            "fk_post_dislikes_user_uuid",
            "phoenix_kit_post_tag_assignments_post_id_fkey",
            "phoenix_kit_post_tag_assignments_tag_id_fkey",
            "phoenix_kit_post_groups_cover_image_id_fkey",
            "fk_post_groups_user_uuid",
            "phoenix_kit_post_group_assignments_group_id_fkey",
            "phoenix_kit_post_group_assignments_post_id_fkey",
            "phoenix_kit_post_media_file_id_fkey",
            "phoenix_kit_post_media_post_id_fkey",
            "phoenix_kit_post_mentions_post_id_fkey",
            "fk_post_mentions_user_uuid",
            "phoenix_kit_post_views_post_id_fkey",
            "fk_post_views_user_uuid",
            "phoenix_kit_comment_likes_comment_id_fkey",
            "fk_comment_likes_user_uuid",
            "phoenix_kit_comment_dislikes_comment_id_fkey",
            "fk_comment_dislikes_user_uuid"
          ] do
        assert statements =~ name,
               "V1 no longer creates #{name} — it must stay shape-identical to core's V135/V168/V185"
      end
    end

    # The 5 unique constraints these schemas assert via `unique_constraint/3`
    # but core never backed with an index — closing them is a shape CHANGE
    # (V2+), never something V1 (pure adoption) creates.
    test "V1 deliberately does NOT create the 5 known-gap unique constraints" do
      statements = Enum.join(Migrations.up_statements(), "\n")

      for name <- [
            "phoenix_kit_post_likes_post_uuid_user_uuid_index",
            "phoenix_kit_post_dislikes_post_uuid_user_uuid_index",
            "phoenix_kit_post_mentions_post_uuid_user_uuid_index",
            "phoenix_kit_comment_likes_comment_uuid_user_uuid_index",
            "phoenix_kit_comment_dislikes_comment_uuid_user_uuid_index"
          ] do
        refute statements =~ name,
               "V1 must not create #{name} — it is a documented V2 gap, not part of this adoption"
      end
    end

    test "up stamps the version marker, and stamps it last" do
      statements = Migrations.up_statements()

      assert List.last(statements) ==
               "COMMENT ON TABLE public.phoenix_kit_posts IS 'pkpo_schema:1'",
             "the marker must be stamped after the DDL it certifies, not before"
    end

    test "applying up to version 0 is not an operation" do
      assert Migrations.up_statements("public", 0) == []
      assert Migrations.up_statements("posts_alt", 0) == []
    end

    test "every up statement is guarded (IF NOT EXISTS / DO-block idempotence)" do
      # V1 runs on installs where core's V135/V168/V185 already created
      # everything, so every statement must be a no-op against an object
      # that is already there.
      ddl = Enum.reject(Migrations.up_statements(), &String.starts_with?(&1, "COMMENT"))

      for stmt <- ddl do
        assert stmt =~ "IF NOT EXISTS",
               "statement is not idempotent against a core-created table:\n#{stmt}"
      end
    end

    # Section order matters: a table must exist before its safety-net ALTER,
    # PK, index or FK guard runs; the marker must certify a finished shape.
    test "statement sections appear in the order tables -> alter-safety-net -> pkeys -> indexes -> fks -> marker" do
      statements = Migrations.up_statements()

      sections =
        Enum.map(statements, fn stmt ->
          cond do
            String.starts_with?(stmt, "CREATE TABLE") -> :table
            String.starts_with?(stmt, "ALTER TABLE") -> :alter
            String.starts_with?(stmt, "COMMENT ON TABLE") -> :marker
            String.starts_with?(stmt, "CREATE") -> :index
            String.starts_with?(stmt, "DO") -> :constraint
          end
        end)

      # Every :constraint DO block is either a pkey or an fk — pkeys are
      # guaranteed to precede indexes, and fks are guaranteed to follow them,
      # by construction (see up_statements/2 below). `Enum.dedup/1`, not
      # `Enum.uniq/1`: uniq would collapse the pkey :constraint run and the
      # later fk :constraint run into one, silently hiding indexes sorted
      # in between the two.
      order = Enum.dedup(sections)

      assert order == [:table, :alter, :constraint, :index, :constraint, :marker],
             "sections are out of order: #{inspect(order)}"
    end
  end

  describe "the chain can never destroy any of the 13 tables" do
    # Compared against the WHOLE expected content, not scanned for a
    # forbidden substring — a substring check only sees statements the
    # builder produced, so anything appended past it (a literal
    # `execute("DROP TABLE ...")` in `up/1`) would be invisible to it. That
    # path is closed by the source-text test below, which checks what is
    # executed rather than what is built.
    test "down/1 emits exactly the marker bookkeeping, in every target and prefix" do
      assert Migrations.down_statements("public", 0) ==
               ["COMMENT ON TABLE public.phoenix_kit_posts IS NULL"]

      assert Migrations.down_statements("public", 1) ==
               ["COMMENT ON TABLE public.phoenix_kit_posts IS 'pkpo_schema:1'"]

      assert Migrations.down_statements("posts_alt", 0) ==
               ["COMMENT ON TABLE posts_alt.phoenix_kit_posts IS NULL"]

      assert Migrations.down_statements("posts_alt", 1) ==
               ["COMMENT ON TABLE posts_alt.phoenix_kit_posts IS 'pkpo_schema:1'"]
    end

    # For `up/1` the expected content is the full set of OPERATIONS rather
    # than the full SQL text. An operation is `{verb, object}`, immune to
    # reformatting and still failing on any statement added, removed or
    # retargeted — including a destructive one, which cannot enter this set
    # without changing it.
    @up_operations [
      {"CREATE TABLE", "phoenix_kit_posts"},
      {"CREATE TABLE", "phoenix_kit_post_comments"},
      {"CREATE TABLE", "phoenix_kit_post_likes"},
      {"CREATE TABLE", "phoenix_kit_post_dislikes"},
      {"CREATE TABLE", "phoenix_kit_post_tags"},
      {"CREATE TABLE", "phoenix_kit_post_tag_assignments"},
      {"CREATE TABLE", "phoenix_kit_post_groups"},
      {"CREATE TABLE", "phoenix_kit_post_group_assignments"},
      {"CREATE TABLE", "phoenix_kit_post_media"},
      {"CREATE TABLE", "phoenix_kit_post_mentions"},
      {"CREATE TABLE", "phoenix_kit_post_views"},
      {"CREATE TABLE", "phoenix_kit_comment_likes"},
      {"CREATE TABLE", "phoenix_kit_comment_dislikes"},
      {"ALTER TABLE", "phoenix_kit_posts"},
      {"DO", "phoenix_kit_posts_pkey"},
      {"DO", "phoenix_kit_post_comments_pkey"},
      {"DO", "phoenix_kit_post_likes_pkey"},
      {"DO", "phoenix_kit_post_dislikes_pkey"},
      {"DO", "phoenix_kit_post_tags_pkey"},
      {"DO", "phoenix_kit_post_groups_pkey"},
      {"DO", "phoenix_kit_post_media_pkey"},
      {"DO", "phoenix_kit_post_mentions_pkey"},
      {"DO", "phoenix_kit_post_views_pkey"},
      {"DO", "phoenix_kit_comment_likes_pkey"},
      {"DO", "phoenix_kit_comment_dislikes_pkey"},
      {"CREATE INDEX", "phoenix_kit_posts_published_at_index"},
      {"CREATE INDEX", "phoenix_kit_posts_scheduled_at_index"},
      {"CREATE UNIQUE INDEX", "phoenix_kit_posts_slug_index"},
      {"CREATE INDEX", "phoenix_kit_posts_status_index"},
      {"CREATE INDEX", "phoenix_kit_posts_status_published_at_index"},
      {"CREATE INDEX", "phoenix_kit_posts_type_index"},
      {"CREATE INDEX", "phoenix_kit_posts_type_status_index"},
      {"CREATE INDEX", "phoenix_kit_posts_user_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_post_comments_depth_index"},
      {"CREATE INDEX", "phoenix_kit_post_comments_parent_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_comments_post_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_comments_post_id_parent_id_depth_index"},
      {"CREATE INDEX", "phoenix_kit_post_comments_status_index"},
      {"CREATE INDEX", "phoenix_kit_post_comments_user_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_post_likes_post_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_likes_user_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_post_dislikes_post_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_dislikes_user_uuid_idx"},
      {"CREATE UNIQUE INDEX", "phoenix_kit_post_tags_slug_index"},
      {"CREATE INDEX", "phoenix_kit_post_tags_usage_count_index"},
      {"CREATE INDEX", "phoenix_kit_post_tag_assignments_post_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_tag_assignments_tag_id_index"},
      {"CREATE UNIQUE INDEX", "phoenix_kit_post_tag_assignments_post_uuid_tag_uuid_index"},
      {"CREATE INDEX", "phoenix_kit_post_groups_is_public_index"},
      {"CREATE INDEX", "phoenix_kit_post_groups_position_index"},
      {"CREATE INDEX", "phoenix_kit_post_groups_user_uuid_idx"},
      {"CREATE UNIQUE INDEX", "phoenix_kit_post_groups_user_uuid_slug_index"},
      {"CREATE INDEX", "phoenix_kit_post_group_assignments_group_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_group_assignments_group_id_position_index"},
      {"CREATE INDEX", "phoenix_kit_post_group_assignments_position_index"},
      {"CREATE INDEX", "phoenix_kit_post_group_assignments_post_id_index"},
      {"CREATE UNIQUE INDEX", "phoenix_kit_post_group_assignments_post_uuid_group_uuid_index"},
      {"CREATE INDEX", "phoenix_kit_post_media_file_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_media_position_index"},
      {"CREATE INDEX", "phoenix_kit_post_media_post_id_index"},
      {"CREATE UNIQUE INDEX", "phoenix_kit_post_media_post_uuid_position_index"},
      {"CREATE INDEX", "phoenix_kit_post_mentions_mention_type_index"},
      {"CREATE INDEX", "phoenix_kit_post_mentions_post_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_mentions_user_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_post_views_post_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_views_post_id_viewed_at_index"},
      {"CREATE INDEX", "phoenix_kit_post_views_session_id_index"},
      {"CREATE INDEX", "phoenix_kit_post_views_viewed_at_index"},
      {"CREATE INDEX", "phoenix_kit_post_views_user_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_comment_likes_comment_id_index"},
      {"CREATE INDEX", "phoenix_kit_comment_likes_user_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_comment_dislikes_comment_id_index"},
      {"CREATE INDEX", "phoenix_kit_comment_dislikes_user_uuid_idx"},
      {"DO", "fk_posts_user_uuid"},
      {"DO", "phoenix_kit_post_comments_parent_id_fkey"},
      {"DO", "phoenix_kit_post_comments_post_id_fkey"},
      {"DO", "fk_post_comments_user_uuid"},
      {"DO", "phoenix_kit_post_likes_post_id_fkey"},
      {"DO", "fk_post_likes_user_uuid"},
      {"DO", "phoenix_kit_post_dislikes_post_id_fkey"},
      {"DO", "fk_post_dislikes_user_uuid"},
      {"DO", "phoenix_kit_post_tag_assignments_post_id_fkey"},
      {"DO", "phoenix_kit_post_tag_assignments_tag_id_fkey"},
      {"DO", "phoenix_kit_post_groups_cover_image_id_fkey"},
      {"DO", "fk_post_groups_user_uuid"},
      {"DO", "phoenix_kit_post_group_assignments_group_id_fkey"},
      {"DO", "phoenix_kit_post_group_assignments_post_id_fkey"},
      {"DO", "phoenix_kit_post_media_file_id_fkey"},
      {"DO", "phoenix_kit_post_media_post_id_fkey"},
      {"DO", "phoenix_kit_post_mentions_post_id_fkey"},
      {"DO", "fk_post_mentions_user_uuid"},
      {"DO", "phoenix_kit_post_views_post_id_fkey"},
      {"DO", "fk_post_views_user_uuid"},
      {"DO", "phoenix_kit_comment_likes_comment_id_fkey"},
      {"DO", "fk_comment_likes_user_uuid"},
      {"DO", "phoenix_kit_comment_dislikes_comment_id_fkey"},
      {"DO", "fk_comment_dislikes_user_uuid"},
      {"COMMENT ON TABLE", "phoenix_kit_posts"}
    ]

    test "up_statements/2 emits exactly these operations and no others" do
      for prefix <- ["public", "posts_alt"] do
        actual = Enum.map(Migrations.up_statements(prefix), &operation/1)

        assert Enum.sort(actual) == Enum.sort(@up_operations),
               """
               up_statements(#{inspect(prefix)}) does not emit the expected set of
               operations.

               unexpected: #{inspect(Enum.sort(actual) -- Enum.sort(@up_operations))}
               missing:    #{inspect(Enum.sort(@up_operations) -- Enum.sort(actual))}

               Every statement this chain emits runs against a core-created
               table. Adding one is a chain version (V2+), not something to
               slip past this list.
               """
      end
    end

    test "the 6 real unique indexes are present, and only they" do
      unique_indexes =
        Migrations.up_statements()
        |> Enum.filter(&String.starts_with?(&1, "CREATE UNIQUE INDEX"))
        |> Enum.map(&operation/1)
        |> Enum.map(&elem(&1, 1))
        |> Enum.sort()

      assert unique_indexes ==
               Enum.sort([
                 "phoenix_kit_posts_slug_index",
                 "phoenix_kit_post_tags_slug_index",
                 "phoenix_kit_post_tag_assignments_post_uuid_tag_uuid_index",
                 "phoenix_kit_post_groups_user_uuid_slug_index",
                 "phoenix_kit_post_group_assignments_post_uuid_group_uuid_index",
                 "phoenix_kit_post_media_post_uuid_position_index"
               ])
    end

    # `ON DELETE ...` is part of the foreign key's DEFINITION — the word
    # DELETE there describes what Postgres does to a child row when the
    # PARENT is deleted, and adoption reproducing core's FK means
    # reproducing core's referential action verbatim. Scanning the raw text
    # for the token would flag it, so the clause is removed before the scan.
    defp strip_referential_actions(statement) do
      String.replace(
        statement,
        ~r/ON\s+(DELETE|UPDATE)\s+(CASCADE|RESTRICT|NO\s+ACTION|SET\s+NULL|SET\s+DEFAULT)/i,
        "ON <referential action>"
      )
    end

    test "the referential-action strip does not blind the destructive scan" do
      forbidden = ~r/\b(DROP TABLE|TRUNCATE|DELETE)\b/i

      mutant =
        "ALTER TABLE public.phoenix_kit_post_likes ADD CONSTRAINT x FOREIGN KEY (post_uuid) " <>
          "REFERENCES public.phoenix_kit_posts(uuid) ON DELETE CASCADE; DROP TABLE public.phoenix_kit_post_likes"

      assert strip_referential_actions(mutant) =~ forbidden

      assert strip_referential_actions("DELETE FROM public.phoenix_kit_posts") =~ forbidden
      assert strip_referential_actions("TRUNCATE public.phoenix_kit_posts") =~ forbidden
    end

    test "no statement anywhere in the data-level chain can drop a table, truncate, or delete rows" do
      forbidden = ~r/\b(DROP TABLE|TRUNCATE|DELETE)\b/i

      for prefix <- ["public", "posts_alt"] do
        for stmt <- Migrations.up_statements(prefix) do
          refute strip_referential_actions(stmt) =~ forbidden,
                 "up_statements(#{inspect(prefix)}) contains: #{stmt}"
        end

        for target <- [0, 1] do
          for stmt <- Migrations.down_statements(prefix, target) do
            refute strip_referential_actions(stmt) =~ forbidden,
                   "down_statements(#{inspect(prefix)}, #{target}) contains: #{stmt}"
          end
        end
      end
    end

    # `{verb, object}` for one statement. The DO block is identified by the
    # constraint it adds, since its verb says nothing about its target.
    defp operation(statement) do
      normalized = statement |> String.replace(~r/\s+/, " ") |> String.trim()

      if String.starts_with?(normalized, "DO ") do
        [_, constraint] = Regex.run(~r/ADD CONSTRAINT (\w+)/, normalized)
        {"DO", constraint}
      else
        [_, verb, object] =
          Regex.run(
            ~r/^(CREATE UNIQUE INDEX|CREATE INDEX|CREATE TABLE|COMMENT ON TABLE|DROP TABLE|DROP INDEX|TRUNCATE|DELETE FROM|ALTER TABLE)(?: IF NOT EXISTS)? (?:\w+\.)?(\w+)/,
            normalized
          )

        {verb, object}
      end
    end
  end

  describe "what reaches the database is what the tests above inspect" do
    # The tests above read `up_statements/2` and `down_statements/2`. The
    # database gets `up/1` and `down/1`. Nothing connected the two, so a
    # literal `execute("DROP TABLE ...")` written straight into `up/1` would
    # have passed every one of them — the guard was watching the data while
    # the function did the work.
    @source "lib/phoenix_kit_posts/migrations.ex"

    test "neither direction executes SQL of its own" do
      source = File.read!(@source)

      refute source =~ ~r/execute\(/,
             """
             #{@source} calls execute/1 with an argument of its own.

             Every statement this chain runs must come from up_statements/2 or
             down_statements/2, because those are what the tests above compare
             against their expected content. A statement executed directly is
             invisible to all of them.
             """

      assert length(Regex.scan(~r/&execute\/1/, source)) == 2,
             "expected exactly two `&execute/1` references — one per direction — " <>
               "in #{@source}"
    end

    test "each direction executes its own builder" do
      source = File.read!(@source)

      assert source =~ ~r/up_statements\(opts\.version\)\s*\|>\s*Enum\.each\(&execute\/1\)/,
             "up/1 no longer pipes up_statements/2 into execute/1 — whatever it " <>
               "runs instead is not what the up_statements-based tests above check"

      assert source =~ ~r/down_statements\(opts\.version\)\s*\|>\s*Enum\.each\(&execute\/1\)/,
             "down/1 no longer pipes down_statements/2 into execute/1 — whatever it " <>
               "runs instead is not what `down/1 emits exactly the marker " <>
               "bookkeeping` checks"
    end

    # Scoped to the two functions' own bodies, not the whole file — the
    # moduledoc legitimately discusses "never drops a table" in prose, which
    # a whole-file, case-insensitive scan would flag as a false positive on
    # the English word rather than a SQL token.
    test "up/1 and down/1 themselves contain no DROP/TRUNCATE/DELETE token" do
      source = File.read!(@source)

      [up_body] = Regex.run(~r/def up\(.*?\n  end\n/s, source)
      [down_body] = Regex.run(~r/def down\(.*?\n  end\n/s, source)

      for {name, body} <- [{"up/1", up_body}, {"down/1", down_body}] do
        refute body =~ ~r/DROP|TRUNCATE|DELETE/i,
               "#{name}'s own body in #{@source} contains a DROP/TRUNCATE/DELETE token"
      end
    end
  end

  describe "V1 stays aligned with core's manifest (while core audits the tables)" do
    alias PhoenixKitPosts.Post
    alias PhoenixKitPosts.PostComment
    alias PhoenixKitPosts.PostGroup
    alias PhoenixKitPosts.PostMention
    alias PhoenixKitPosts.PostTag
    alias PhoenixKitPosts.PostView

    @width_schemas %{
      "phoenix_kit_posts" => Post,
      "phoenix_kit_post_comments" => PostComment,
      "phoenix_kit_post_groups" => PostGroup,
      "phoenix_kit_post_mentions" => PostMention,
      "phoenix_kit_post_tags" => PostTag,
      "phoenix_kit_post_views" => PostView
    }

    # The lesson phoenix_kit_legal paid for once (three disagreeing DDLs of
    # one table): never a second copy of a width. Parsed back out of each
    # CREATE (and, for `phoenix_kit_posts`, its safety-net ALTER too) rather
    # than trusted, so a hard-coded number slipped into up_statements/2
    # instead of a schema's column_widths/0 fails here even though the two
    # happen to agree today.
    test "every varchar width in each CREATE/ALTER is that table's schema's column_widths/0" do
      statements = Migrations.up_statements("public", 1)

      for {table, schema} <- @width_schemas do
        columns = v1_columns(statements, table)

        parsed =
          columns
          |> Enum.filter(fn {_col, %{type: type}} -> type =~ "character varying" end)
          |> Map.new(fn {col, %{type: type}} ->
            [_, width] = Regex.run(~r/character varying\((\d+)\)/, type)
            {String.to_existing_atom(col), String.to_integer(width)}
          end)

        assert parsed == schema.column_widths(),
               """
               #{table}: the CREATE/ALTER widths and #{inspect(schema)}.column_widths/0 disagree.

               parsed from DDL: #{inspect(parsed)}
               declared:        #{inspect(schema.column_widths())}
               """
      end
    end

    # The same shape, parsed back out of the CREATE TABLE V1 emits for
    # `table` — merged with any safety-net ALTER TABLE ... ADD COLUMN
    # statement for that same table (only `phoenix_kit_posts.time_zone`
    # today), since that column is deliberately NOT in the CREATE TABLE body
    # (see the moduledoc: core's V135 never had it, only V185 added it).
    defp v1_columns(statements, table) do
      create = table_create(statements, table)

      base =
        ~r/^\s*"(\w+)"\s+(.+?),?$/m
        |> Regex.scan(create)
        |> Map.new(fn [_line, name, definition] -> {name, parse_column(definition)} end)

      Map.merge(base, table_alter_columns(statements, table))
    end

    defp table_create(statements, table) do
      Enum.find(
        statements,
        &String.starts_with?(&1, "CREATE TABLE IF NOT EXISTS public.#{table} (")
      )
    end

    defp table_alter_columns(statements, table) do
      prefix = "ALTER TABLE public.#{table} ADD COLUMN IF NOT EXISTS "

      statements
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Map.new(fn statement ->
        definition = String.replace_prefix(statement, prefix, "")
        [_, name, rest] = Regex.run(~r/^"(\w+)"\s+(.+)$/, definition)
        {name, parse_column(rest)}
      end)
    end

    defp parse_column(definition) do
      {definition, not_null} =
        case String.replace_suffix(definition, " NOT NULL", "") do
          ^definition -> {definition, false}
          trimmed -> {trimmed, true}
        end

      case String.split(definition, " DEFAULT ", parts: 2) do
        [type] -> %{type: type, default: nil, not_null: not_null}
        [type, default] -> %{type: type, default: default, not_null: not_null}
      end
    end
  end
end
