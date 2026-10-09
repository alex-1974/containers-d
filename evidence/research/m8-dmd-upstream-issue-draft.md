# Upstream DMD issue draft — nested placement new crash

Proposed title:

```text
[REG2.112] Placement new of nested local struct segfaults
```

## Summary

DMD 2.112.1 and 2.113.0 generate a program that segfaults when placement
`new` constructs a function-local nested struct. The same code works with
DMD 2.111.0 and LDC 1.41/1.42/1.43.

The failure is not specific to move construction: a normal `int`
constructor also crashes. Making the local struct `static` removes the hidden
context (`__traits(isNested, T) == false`) and the placement construction
succeeds.

## Minimal reproducer

```d
void main()
{
    struct S
    {
        int value;

        this(int value)
        {
            this.value = value;
        }
    }

    static assert(__traits(isNested, S));

    align(S.alignof) ubyte[S.sizeof] storage = void;
    auto target = cast(S*) storage.ptr;

    auto placed = new (*target) S(51);

    assert(placed is target);
    assert(placed.value == 51);
}
```

Compile and run:

```sh
dmd repro.d && ./repro
```

## Observed

- DMD 2.111.0: PASS
- DMD 2.112.1: SIGSEGV (exit 139)
- DMD 2.113.0: SIGSEGV (exit 139)
- LDC 1.41.0 (frontend 2.111): PASS
- LDC 1.42.0 (frontend 2.112.1): PASS
- LDC 1.43.0 (frontend 2.113): PASS

Instrumentation immediately before and after the placement expression shows
that the failing DMD programs enter the placement expression and never return
from it.

## Control

The same function-local type declared `static` succeeds:

```d
void main()
{
    static struct S
    {
        int value;

        this(int value)
        {
            this.value = value;
        }
    }

    static assert(!__traits(isNested, S));

    align(S.alignof) ubyte[S.sizeof] storage = void;
    auto target = cast(S*) storage.ptr;

    auto placed = new (*target) S(51);

    assert(placed is target);
    assert(placed.value == 51);
}
```

Ordinary typed-storage construction of the nested struct also succeeds.

## Specification context

The language specification describes nested structs as structs carrying a
hidden context pointer and does not exclude them from placement new. Placement
new permits struct construction in sufficiently large mutable storage and
passes constructor arguments to the struct constructor.

Related but apparently distinct issues:

- #20950 — placement new and implicit copy constructor selection
- #21222 — placement new returns bad pointer
- #20090 — static variable of nested type causes runtime crash
- #23355 — object.destroy problems for local self-referential types

## Regression

The behavior changes between DMD 2.111.0 and DMD 2.112.1.

Tested on Linux x86_64 / Ubuntu 24.04.
