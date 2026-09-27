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


/**
 * Audited language-level element operations for raw-slot containers.
 *
 * This is intentionally not a policy surface. It centralizes operations whose
 * correctness depends on D object-lifetime rules so that container families do
 * not each recreate their own trusted placement-construction bridge.
 */
/**
 * Move-construct T directly in an unused, suitably aligned slot.
 *
 * Function-template form: the operation is instantiated for T at the consumer
 * and preserves the @safe/@system distinction through mutually exclusive
 * template constraints.
 */
package(containers) T* placementMoveConstruct(T)(
    T* target,
    ref T source) @trusted
if (hasLanguageMoveConstructor!T &&
    safeLanguageMoveConstructible!T)
{
    assert(target !is null);
    return new (*target) T(__rvalue(source));
}

/// ditto
package(containers) T* placementMoveConstruct(T)(
    T* target,
    ref T source) @system
if (hasLanguageMoveConstructor!T &&
    !safeLanguageMoveConstructible!T)
{
    assert(target !is null);
    return new (*target) T(__rvalue(source));
}

package(containers) struct ElementLifetimeOps(T)
{
    static if (hasLanguageMoveConstructor!T)
    {
        static if (safeLanguageMoveConstructible!T)
        {
            /**
             * Move-construct T directly in an unused, suitably aligned slot.
             *
             * The caller owns the proof that target denotes unused storage for
             * exactly one T and does not overlap source. T's own language move
             * construction has independently been shown callable from @safe
             * code, so only placement-new's raw-storage transition is trusted.
             */
            pragma(inline, true)
            static T* placementMoveConstruct(
                T* target,
                ref T source) @trusted
            {
                assert(target !is null);
                return new (*target) T(__rvalue(source));
            }
        }
        else
        {
            /**
             * Same raw-slot operation for T whose language move constructor is
             * not callable from @safe code.
             *
             * The helper intentionally remains @system; containers-d must not
             * upgrade an unsafe element operation merely because the target
             * slot itself is valid.
             */
            pragma(inline, true)
            static T* placementMoveConstruct(
                T* target,
                ref T source) @system
            {
                assert(target !is null);
                return new (*target) T(__rvalue(source));
            }
        }
    }
}

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

    private struct SelfReferentialMove
    {
        int value;
        int* self;

        this(int value) @system @nogc nothrow
        {
            this.value = value;
            self = &this.value;
        }

        @disable this(ref return scope SelfReferentialMove rhs);

        this(return scope SelfReferentialMove rhs) @system @nogc nothrow
        {
            value = rhs.value;
            self = &this.value;
            rhs.value = -1;
            rhs.self = null;
        }

        bool selfValid() @safe @nogc nothrow
        {
            return self is &value;
        }
    }

    private struct SystemMove
    {
        int value;

        @disable this(ref return scope SystemMove rhs);

        this(return scope SystemMove rhs) @system @nogc nothrow
        {
            value = rhs.value;
            rhs.value = -1;
        }
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


unittest
{
    // Safe language move remains callable through the shared raw-slot bridge
    // from @safe code. Use a null pointer only in this compile-time probe; the
    // helper is not executed.
    static assert(__traits(compiles, {
        void probe(ref MoveOnly source) @safe
        {
            MoveOnly* target = null;
            if (target !is null)
                ElementLifetimeOps!MoveOnly.placementMoveConstruct(
                    target, source);
        }
    }));

    // containers-d must not upgrade a @system move constructor to @safe.
    static assert(!__traits(compiles, {
        void probe(ref SystemMove source) @safe
        {
            SystemMove* target = null;
            if (target !is null)
                ElementLifetimeOps!SystemMove.placementMoveConstruct(
                    target, source);
        }
    }));
}

unittest
{
    // Placement move must construct directly at the final slot address. This
    // is required for self-referential move constructors and is the exact
    // semantic used by the existing ring-buffer insertion paths.
    align(SelfReferentialMove.alignof)
        ubyte[SelfReferentialMove.sizeof] raw = void;

    auto source = SelfReferentialMove(73);

    auto target = (() @trusted =>
        cast(SelfReferentialMove*) raw.ptr)();

    auto placed =
        ElementLifetimeOps!SelfReferentialMove.placementMoveConstruct(
            target, source);

    assert(placed is target);
    assert(placed.value == 73);
    assert(placed.selfValid);
    assert(source.value == -1);
    assert(source.self is null);

    destroy!false(*placed);
}
