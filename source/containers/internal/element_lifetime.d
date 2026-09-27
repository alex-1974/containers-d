/**
 * Internal element-lifetime classification shared by container-family research.
 *
 * This module is deliberately package-internal. It identifies language-level
 * element capabilities; it does not expose consumer-selectable lifetime
 * policies.
 */
module containers.internal.element_lifetime;

import std.traits : hasElaborateDestructor, hasIndirections;

/**
 * Whether T can be copy-constructed from an lvalue T using the language
 * operation containers actually require.
 *
 * This deliberately avoids depending on broader Phobos copyability traits whose
 * exact meaning has varied across compiler/library revisions.
 */
package(containers) enum bool elementCopyConstructible(T) =
    __traits(compiles, {
        void probe(ref T source)
        {
            T copy = source;
        }
    });

/**
 * Whether ordinary language move construction of T is accepted from @safe
 * code.
 *
 * Placement construction into raw storage remains a separate trusted
 * operation. This trait only classifies T's own move-construction contract.
 */
package(containers) enum bool safeLanguageMoveConstructible(T) =
    __traits(compiles, {
        void probe(ref T source) @safe
        {
            T target = __rvalue(source);
        }
    });

/// Whether T declares a D language move constructor.
package(containers) enum bool hasLanguageMoveConstructor(T) =
    __traits(hasMoveConstructor, T);

/// Whether ending a live T lifetime requires explicit destruction.
package(containers) enum bool elementNeedsDestruction(T) =
    hasElaborateDestructor!T;

/// Whether raw storage for T must preserve GC visibility of possible pointers.
package(containers) enum bool elementHasIndirections(T) =
    hasIndirections!T;

version (unittest)
{
    private struct MoveOnly
    {
        int value;

        @disable this(ref return scope MoveOnly rhs);

        this(return scope MoveOnly rhs) @safe @nogc nothrow
        {
            value = rhs.value;
            rhs.value = -1;
        }
    }

    private struct WithDestructor
    {
        ~this() @safe @nogc nothrow {}
    }

    private struct WithIndirection
    {
        Object reference;
    }
}

unittest
{
    static assert(elementCopyConstructible!int);
    static assert(!hasLanguageMoveConstructor!int);
    static assert(!elementNeedsDestruction!int);
    static assert(!elementHasIndirections!int);

    static assert(!elementCopyConstructible!MoveOnly);
    static assert(hasLanguageMoveConstructor!MoveOnly);
    static assert(safeLanguageMoveConstructible!MoveOnly);

    static assert(elementNeedsDestruction!WithDestructor);
    static assert(elementHasIndirections!WithIndirection);
}
