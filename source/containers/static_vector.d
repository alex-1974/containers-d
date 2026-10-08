/**
 * Fixed-capacity contiguous vector.
 *
 * Public module for $(LREF StaticVector). The implementation remains in the
 * package-internal family module so representation details are not a public
 * customization surface.
 */
module containers.static_vector;

import containers.internal.static_vector :
    InternalStaticVector = StaticVector;

/**
 * Fixed-capacity contiguous vector for small bounded sequences.
 *
 * StaticVector stores its elements inline in the vector object. Use it when the
 * maximum element count is known at compile time and heap allocation for the
 * container itself is undesirable. The live elements always form one
 * contiguous prefix, so normal indexing and D slices work without copying.
 *
 * `pushBack` is the precondition-based hot path when the caller already knows
 * spare capacity exists. `tryPushBack` performs the checked form. The vector
 * never grows beyond `Capacity`.
 *
 * Params:
 *   T = element type
 *   Capacity = compile-time maximum number of live elements; greater than zero
 *
 * Init:
 *   `.init` is a valid empty vector.
 *
 * Allocation:
 *   The container stores its backing memory inline and performs no backing
 *   allocation. Operations performed by `T` may allocate.
 *
 * Thread_Safety:
 *   Instances are not synchronized. Concurrent mutation requires external
 *   synchronization.
 */
alias StaticVector = InternalStaticVector;

/// Build a short bounded sequence without allocating container storage.
unittest
{
    StaticVector!(int, 4) points;

    // Use the checked form when capacity is part of normal control flow.
    assert(points.tryPushBack(10));
    assert(points.tryPushBack(20));

    // The live prefix is contiguous and can be passed as an ordinary slice.
    assert(points[] == [10, 20]);

    // Reuse the inline storage after removing temporary values.
    points.popBack();
    points.pushBack(30);
    assert(points[] == [10, 30]);
}
