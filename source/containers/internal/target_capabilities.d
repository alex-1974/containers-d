/**
 * Compiler/target capabilities qualified by containers-d evidence.
 *
 * Keep machine-specific decisions here rather than scattering version checks
 * through container algorithms. A capability is enabled only for combinations
 * that have direct repository evidence; unknown combinations use the
 * conservative implementation.
 */
module containers.internal.target_capabilities;

private alias NativePointer = void*;

/// Alignment guaranteed by ordinary native pointer placement.
package(containers) enum size_t nativePointerAlignment =
    NativePointer.alignof;

/**
 * Strongest inline aggregate-field alignment currently qualified to propagate
 * correctly through an enclosing aggregate on this compiler/target.
 *
 * LDC 1.41 on Linux x86_64 is directly qualified through issue #31 probes up
 * to align(64). DMD 2.111 on the same target is not: an align(64) field can be
 * embedded at offset 8. Other compiler/target combinations deliberately fall
 * back to native pointer alignment until their own matrix row is qualified.
 */
version (LDC)
{
    version (linux)
    {
        version (X86_64)
        {
            package(containers) enum size_t
                qualifiedInlineEmbeddedAlignment = 64;
        }
        else
        {
            package(containers) enum size_t
                qualifiedInlineEmbeddedAlignment =
                    nativePointerAlignment;
        }
    }
    else
    {
        package(containers) enum size_t
            qualifiedInlineEmbeddedAlignment =
                nativePointerAlignment;
    }
}
else
{
    package(containers) enum size_t
        qualifiedInlineEmbeddedAlignment =
            nativePointerAlignment;
}
