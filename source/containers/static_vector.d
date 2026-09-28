/**
 * Fixed-capacity contiguous vector.
 *
 * Promotion candidate for the next containers-d family.
 *
 * This module is intentionally not re-exported from the package root yet.
 * The direct import surface is being qualified before package-root admission.
 */
module containers.static_vector;

import containers.internal.static_vector :
    InternalStaticVector = StaticVector;

/// Fixed-capacity, variable-length contiguous inline vector.
alias StaticVector = InternalStaticVector;
