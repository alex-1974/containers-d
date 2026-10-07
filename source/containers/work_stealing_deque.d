/**
 * Candidate public surface for the bounded single-owner / multi-thief
 * work-stealing deque family.
 *
 * This module exists on the M5 research branch so the intended caller-facing
 * API can be compiled and documented before production promotion.
 */
module containers.work_stealing_deque;

public import containers.research.work_stealing_deque :
    WorkStealingTakeResult;

import containers.research.work_stealing_deque :
    ResearchWorkStealingDeque;

/// Bounded fixed-capacity single-owner / multi-thief work-stealing deque.
alias WorkStealingDeque = ResearchWorkStealingDeque;
