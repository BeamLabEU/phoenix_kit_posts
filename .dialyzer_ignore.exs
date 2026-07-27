[
  # `PhoenixKit.Settings.get_editor_mode/0` ships in a phoenix_kit release
  # newer than our `~> 1.7.189` floor, so it is legitimately missing from the
  # cores this module still supports. `Web.Edit.default_editor_mode/0` guards
  # the call with `function_exported?/3` and falls back to `:hybrid`, which is
  # precisely the pattern dialyzer can't see through. Drop this entry once the
  # pin moves to a core that exports the function.
  {"lib/phoenix_kit_posts/web/edit.ex", :call_to_missing}
]
