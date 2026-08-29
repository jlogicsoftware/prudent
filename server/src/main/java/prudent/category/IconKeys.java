package prudent.category;

import java.util.Set;

/**
 * The icon keys a category may carry — the exact set the client ships an {@code IconData} for.
 *
 * <p><strong>Why the server validates this at all.</strong> The contract carries a key rather than
 * an icon code point so that Flutter's icon tree-shaking keeps working, which means the client
 * holds a {@code const Map<String, IconData>} of exactly the icons compiled into it. A key outside
 * that map has no icon to render. The client's documented behaviour is to fall back rather than
 * throw — a category created by a newer client must not break an older one — but a fallback is a
 * recovery from someone else's mistake, not a licence to store nonsense. Refusing the write is what
 * keeps the fallback path rare enough to stay a safety net.
 *
 * <p><strong>This set is duplicated on the client, and that is a real cost.</strong> The two lists
 * must agree, and nothing in the build checks that they do: adding a key here without adding the
 * icon there produces categories that render the fallback for everyone. The honest fix is to
 * generate both from one source, which is a contract change rather than a Phase 2 change — the
 * keys would move into the {@code .proto} as an enum. That is not done now because an enum
 * forecloses a user-supplied icon set, which is a product question nobody has asked yet; until it
 * is asked, the duplication is named here and in the client's map.
 */
public final class IconKeys {

  /**
   * The permitted keys. Ordered as the category form presents them, though nothing depends on the
   * order — {@code Set.of} makes no promise about it, which is why the client owns presentation.
   */
  public static final Set<String> PERMITTED =
      Set.of("work", "leisure", "food", "restaurant", "medicine");

  private IconKeys() {}

  /**
   * Whether a key names an icon the client can render.
   *
   * @param key the candidate, possibly {@code null} or blank
   * @return {@code true} only for a key in {@link #PERMITTED}
   */
  public static boolean permits(String key) {
    return key != null && PERMITTED.contains(key);
  }
}
