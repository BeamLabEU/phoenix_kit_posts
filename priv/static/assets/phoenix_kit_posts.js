// phoenix_kit_posts JS hooks — folded into the host's LiveSocket by core's
// :phoenix_kit_js_sources compiler (see PhoenixKit.Module.js_sources/0).
//
// This used to be an inline <script> at the bottom of web/edit.html.heex that
// assigned window.postsEditorInsertMedia and added a window listener for
// `phx:insert-media`. That works on a hard page load — the script runs during
// HTML parse, before app.js constructs the LiveSocket — and silently does
// nothing after a LiveView NAVIGATION into the editor, because morphdom never
// executes a <script> tag it inserts. Inserting an image or a video into the
// post body was therefore dead on every live_redirect into /admin/posts/new
// or /admin/posts/:id/edit.
//
// Hook names are namespaced (PhoenixKitPosts*) because the final fold into
// window.PhoenixKitHooks is last-write-wins across every module's bundle and
// core's own hooks.
(function () {
  "use strict";

  window.PhoenixKitPostsHooks = window.PhoenixKitPostsHooks || {};

  // Inserts one media item at the caret of the Leaf editor identified by
  // `editorId`. Visual/hybrid modes get a real <img> node at the selection;
  // the markdown surface gets Markdown image syntax at the cursor. Both
  // dispatch `input` so Leaf picks the change up and pushes it to the server.
  function insertMedia(editorId, fileUrl, mediaType) {
    if (!fileUrl) return;

    const altText = mediaType === "image" ? "Image description" : "Video";

    // Visual (contenteditable) surface first.
    const visualEl = document.getElementById(editorId + "-visual");
    if (visualEl) {
      visualEl.focus();
      const img = document.createElement("img");
      img.src = fileUrl;
      img.alt = altText;

      const sel = window.getSelection();
      // Only reuse the selection when it is actually inside this editor —
      // otherwise a stale range (the modal's own focus, say) would drop the
      // node somewhere else on the page.
      const range =
        sel && sel.rangeCount ? sel.getRangeAt(0) : null;

      if (range && visualEl.contains(range.commonAncestorContainer)) {
        range.deleteContents();
        range.insertNode(img);
        range.setStartAfter(img);
        range.collapse(true);
        sel.removeAllRanges();
        sel.addRange(range);
      } else {
        visualEl.appendChild(img);
      }

      visualEl.dispatchEvent(new Event("input", { bubbles: true }));
      return;
    }

    // Markdown surface fallback.
    const textarea = document.getElementById(editorId + "-markdown-textarea");
    if (!textarea) return;

    const template = "![" + altText + "](" + fileUrl + ")";
    const start = textarea.selectionStart || 0;
    const end = textarea.selectionEnd || 0;
    const currentValue = textarea.value;

    textarea.value =
      currentValue.substring(0, start) + template + currentValue.substring(end);

    const newPos = start + template.length;
    textarea.selectionStart = textarea.selectionEnd = newPos;
    textarea.focus();

    textarea.dispatchEvent(new Event("input", { bubbles: true }));
  }

  // Consumes `push_event("insert-media", %{items: [%{url, type}]})` from
  // PhoenixKitPosts.Web.Edit. LiveView dispatches a pushed event on `window`
  // as `phx:<event>`, so the listener is a window listener bound in mounted()
  // and removed in destroyed() — no listener survives the editor page.
  //
  // The element carrying this hook names its editor with
  // `data-editor-id` (the same id passed to <.leaf_editor>).
  window.PhoenixKitPostsHooks.PhoenixKitPostsMediaInserter = {
    mounted() {
      this.editorId = this.el.dataset.editorId;

      this.onInsertMedia = (event) => {
        const detail = event.detail || {};
        const items = detail.items || [];
        items.forEach((item) => {
          insertMedia(this.editorId, item.url, item.type);
        });
      };

      window.addEventListener("phx:insert-media", this.onInsertMedia);
    },

    updated() {
      // The editor id is rendered, so keep it in step with the DOM.
      this.editorId = this.el.dataset.editorId;
    },

    destroyed() {
      window.removeEventListener("phx:insert-media", this.onInsertMedia);
    },
  };
})();
