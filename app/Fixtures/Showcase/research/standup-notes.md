# Standup notes

**Monday.** Token format signed off. Dual-write flag is in review.

**Tuesday.** Load test on the edge verifier: 18k req/s per node, CPU-bound on
signature checks. Switching to Ed25519 should halve it.

**Wednesday.** Blocked on the vault rotation job; it needs the new IAM role.
