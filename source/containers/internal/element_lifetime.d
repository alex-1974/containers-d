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
 * Whether the current frontend accepts ordinary language move construction of
 * T from @safe code through __rvalue(source).
 *
 * This is deliberately a compiler-qualified capability rather than a timeless
 * property of T. Frontend 2.112+ rejects some __rvalue(local) expressions from
 * @safe code even when T's declared move constructor is @safe.
 *
 * Placement construction into raw storage remains a separate audited bridge.
 * containers-d uses this capability only to decide whether that bridge may be
 * exposed as @trusted/@safe-callable or must remain @system.
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
 * Injects the audited placement-move bridge into a consuming aggregate.
 *
 * DMD 2.111 does not inline the equivalent imported helper across the module
 * boundary in the M4.2 instruction-count probe. A typed template mixin keeps
 * the source definition shared while generating the helper in the consumer's
 * scope. It injects no state and refers to no host fields.
 *
 * HasMove and SafeMove capture the centrally classified T traits at template
 * instantiation so the mixed code has no additional import requirements.
 */
/**
 * Injects element destruction for one live T object.
 *
 * This operation intentionally stops at the language lifetime boundary. It
 * does not clear the backing bytes after destruction; vacated-slot sanitation
 * belongs to the storage implementation because GC visibility is a property of
 * the backing storage.
 */
package(containers) mixin template EndElementLifetimeOps(
    T,
    bool NeedsDestroy = elementNeedsDestruction!T)
{
    private static void endElementLifetime(T* slot)
    {
        assert(slot !is null);

        static if (NeedsDestroy)
            destroy!false(*slot);
    }
}

package(containers) mixin template PlacementMoveOps(
    T,
    bool HasMove = hasLanguageMoveConstructor!T,
    bool SafeMove = safeLanguageMoveConstructible!T)
{
    static if (HasMove)
    {
        static if (SafeMove)
        {
            private static T* placementMoveConstruct(
                T* target,
                ref T source) @trusted
            {
                assert(target !is null);
                return new (*target) T(__rvalue(source));
            }
        }
        else
        {
            private static T* placementMoveConstruct(
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
    import core.lifetime : emplace;

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

    private struct DestructorOps
    {
        mixin EndElementLifetimeOps!WithDestructor;
    }

    private struct TrivialEndOps
    {
        mixin EndElementLifetimeOps!int;
    }

    private struct MoveOnlyOps
    {
        mixin PlacementMoveOps!MoveOnly;
    }

    private struct SystemMoveOps
    {
        mixin PlacementMoveOps!SystemMove;
    }

    private struct SelfReferentialMoveOps
    {
        mixin PlacementMoveOps!SelfReferentialMove;
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

    // safeLanguageMoveConstructible is intentionally frontend-qualified.
    // DMD/LDC based on frontend 2.111 accept this __rvalue form from @safe
    // code; frontend 2.112+ may reject it independently of the move
    // constructor's own @safe annotation.
    static assert(elementNeedsDestruction!WithDestructor);
    static assert(elementHasIndirections!WithIndirection);
}


unittest
{
    // The generated bridge must exactly follow the frontend-qualified
    // safeLanguageMoveConstructible capability. Use a null pointer only in
    // this compile-time probe; the helper is never executed.
    enum bool bridgeCallableFromSafe =
        __traits(compiles, {
            void probe(ref MoveOnly source) @safe
            {
                MoveOnly* target = null;
                if (target !is null)
                    MoveOnlyOps.placementMoveConstruct(
                        target, source);
            }
        });

    static assert(
        bridgeCallableFromSafe ==
        safeLanguageMoveConstructible!MoveOnly);

    // containers-d must not upgrade a @system move constructor to @safe.
    static assert(!__traits(compiles, {
        void probe(ref SystemMove source) @safe
        {
            SystemMove* target = null;
            if (target !is null)
                SystemMoveOps.placementMoveConstruct(
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
        SelfReferentialMoveOps.placementMoveConstruct(
            target, source);

    assert(placed is target);
    assert(placed.value == 73);
    assert(placed.selfValid);
    assert(source.value == -1);
    assert(source.self is null);

    destroy!false(*placed);
}


unittest
{
    // The shared operation ends the language lifetime exactly once for a type
    // with an elaborate destructor.
    static int destroyed;

    struct CountedDestructor
    {
        ~this()
        {
            ++destroyed;
        }
    }

    struct CountedDestructorOps
    {
        mixin EndElementLifetimeOps!CountedDestructor;
    }

    align(CountedDestructor.alignof)
        ubyte[CountedDestructor.sizeof] raw = void;

    auto slot = (() @trusted =>
        cast(CountedDestructor*) raw.ptr)();

    emplace(slot);
    destroyed = 0;

    CountedDestructorOps.endElementLifetime(slot);
    assert(destroyed == 1);
}

unittest
{
    // For a trivial T, ending the language lifetime requires no destructor.
    int value = 42;
    TrivialEndOps.endElementLifetime(&value);
    assert(value == 42);
}
