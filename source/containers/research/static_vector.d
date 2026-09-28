/**
 * Research-only import surface for the M4.3 StaticVector candidate.
 *
 * This module exists only to let real external consumers qualify the candidate
 * before any package-root/public-release decision. Importing this module is not
 * a compatibility promise.
 */
module containers.research.static_vector;

import containers.internal.static_vector :
    InternalStaticVector = StaticVector;

/// Research alias for the package-internal M4.3 candidate.
alias StaticVector = InternalStaticVector;
