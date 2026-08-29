package prudent.health;

import zen.core.http.ZenStatus;

/**
 * The HTTP status codes Prudent's resources annotate with, framework codes and Prudent's own
 * reachable through one type.
 *
 * <p><strong>This type is also what proves the jZen dependency seam resolves.</strong> Prudent
 * consumes the framework from a sibling checkout at {@code ../jZen}, through a parent POM declared
 * with an empty {@code <relativePath/>} and resolved from the local Maven repository (see the long
 * comment in {@code server/pom.xml}, and {@code docs/DECISIONS.md} ADR-001). A module that compiles
 * because it depends on nothing proves nothing about that arrangement — so the seam is proven by
 * actually compiling against a framework type, and {@link ZenStatus} is the one jZen ADR-026 used
 * when it verified the same question from the other side.
 *
 * <p><strong>It adds no codes of its own yet, and that is honest rather than incomplete.</strong>
 * Prudent has no resources until Phase 2; inventing a status code before there is a response that
 * returns it would be a surface that does not exist. What this type does today is inherit
 * {@code ZenStatus}'s constants under a Prudent-owned name, so the first resource written in
 * Phase 2 imports {@code PrudentStatus} rather than {@code ZenStatus} — and the day Prudent needs a
 * code the framework does not define, it is added here and every existing annotation keeps working.
 *
 * <p><strong>{@code extends}, never {@code implements}.</strong> Implementing a constant-holding
 * interface is the "constant interface antipattern" (Effective Java, Item 22): it leaks the
 * constants into the implementing type's exported API. This is a namespace of values, not a type to
 * implement. The inherited members are implicitly {@code public static final String} and remain
 * compile-time constants, which is the whole point — a Java annotation element must be a constant
 * expression (JLS 15.29), so these have to be literals rather than method calls.
 *
 * <pre>{@code
 * @APIResponse(responseCode = PrudentStatus.OK, ...)        // inherited from ZenStatus
 * }</pre>
 */
public interface PrudentStatus extends ZenStatus {
}
