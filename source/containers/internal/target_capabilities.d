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
 * LDC 1.41/1.42/1.43 on Linux x86_64 and AArch64 are directly qualified
 * through issue #31 probes up to align(64). DMD 2.111/2.112/2.113 on Linux
 * x86_64 are not: an align(64) field can be embedded at offset 8. Other
 * compiler/target combinations deliberately fall back to native pointer
 * alignment until their own matrix row is qualified.
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
        else version (AArch64)
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


/**
 * Whether hot exact-T lvalue insertion should use a locally generated simple
 * copy-construction bridge instead of core.lifetime.emplace.
 *
 * DMD 2.111/2.112/2.113 on Linux x86_64 retain substantial out-of-line
 * emplace/copyEmplace cost for simple structs. Dedicated Callgrind probes show
 * that local fixed-size copying removes most of that cost. LDC already lowers
 * ordinary emplace to C++-class code and deliberately keeps the standard path.
 *
 * Unknown DMD targets remain conservative until independently qualified.
 */
version (DigitalMars)
{
    version (linux)
    {
        version (X86_64)
            package(containers) enum bool preferLocalSimpleCopyConstruction = true;
        else
            package(containers) enum bool preferLocalSimpleCopyConstruction = false;
    }
    else
    {
        package(containers) enum bool preferLocalSimpleCopyConstruction = false;
    }
}
else
{
    package(containers) enum bool preferLocalSimpleCopyConstruction = false;
}
