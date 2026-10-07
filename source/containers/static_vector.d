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

/// Fixed-capacity, variable-length contiguous inline vector.
alias StaticVector = InternalStaticVector;
