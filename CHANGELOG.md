# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-05-16

### Added

- Initial release of the RaptorQ codec (RFC 6330).
- `Raptorq.encode/2` to compute intermediate symbols for a block of `K` source symbols.
- `Raptorq.repair/4` to generate encoding symbols for arbitrary ISIs.
- `Raptorq.decode/3` to recover source data from any `K'` distinct symbols.
- Dense reference solver (`Raptorq.Solver`) and O(L²) 5-phase sparse solver (`Raptorq.Solver5`).
- Precomputed tables in `priv/` (SIOP, Deg, OCT_LOG/EXP, V0–V3).
