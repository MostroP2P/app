# Mostro v2 Specification

This directory contains the specification for **Mostro v2** — the next generation of the Mostro P2P exchange platform.

## v2 Features & Specs

### New Features

- [NOSTR_EXCHANGE_RATES.md](./NOSTR_EXCHANGE_RATES.md) — Censorship-resistant exchange rates via Nostr (NIP-33)

### Core Architecture

**Note:** The following specs are planned but not yet implemented in this repository. They exist in the main project documentation.

- ~~[ARCHITECTURE.md](./ARCHITECTURE.md)~~ — System architecture and component design *(planned)*
- ~~[DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md)~~ — UI/UX design system and guidelines *(planned)*
- ~~[PROTOCOL.md](./PROTOCOL.md)~~ — Mostro protocol specification *(see [mostro repo](https://github.com/MostroP2P/mostro))*

### v1 Reference Documentation

The [v1-reference/](./v1-reference/) directory contains comprehensive documentation of the Flutter-based v1 implementation. These specs serve as:

- **Migration guide** — Understanding existing features for v2 implementation
- **Feature reference** — Detailed behavior of current app functionality
- **Cross-platform patterns** — Lessons learned from v1 architecture

See [v1-reference/README.md](./v1-reference/README.md) for the complete list of v1 specs.

---

## Using This Specification

### For Developers

Each spec document follows a standard structure:

- **Overview** — What the feature does
- **Architecture** — System design and component relationships
- **Implementation** — Code examples and integration patterns
- **Security** — Threat model and mitigations
- **Testing** — Test strategy and checklist
- **Cross-References** — Related specs and dependencies

### For SpecKit Generation

These specs are written to be consumed by **SpecKit** — the automated app generation tool for Mostro v2. When a spec is ready for implementation:

1. Tag the spec with implementation status (e.g., `status: ready`)
2. Run SpecKit generator: `speckit generate --spec FEATURE_NAME.md`
3. Review generated code in `src/` (Rust) and `lib/` (Flutter)
4. Test, refine, deploy

### Migration Notes

When migrating features from v1 → v2:

- ✅ **Keep Flutter:** Platform-specific UI, HTTP integrations
- ✅ **Move to Rust:** Core logic, crypto, protocol handling (via flutter_rust_bridge 2.x)
- ⚠️ **Refactor:** Simplify state management, reduce Riverpod complexity
- 🚨 **Security:** All v2 features must include threat model documentation

---

## Contributing

### Adding a New Spec

1. Create `FEATURE_NAME.md` in `.specify/`
2. Follow the template structure (see existing specs)
3. Include cross-references to related specs
4. Add migration notes if replacing v1 feature
5. Submit PR with `docs:` prefix in commit message

### Updating an Existing Spec

1. Make changes to the spec file
2. Update `Cross-References` section if dependencies changed
3. Increment version/date in spec metadata (if tracked)
4. Submit PR explaining the rationale for changes

### Spec Review Checklist

- [ ] Clear overview and motivation
- [ ] Security considerations documented
- [ ] Code examples valid (compile/test)
- [ ] Cross-references up-to-date
- [ ] Migration notes (if applicable)
- [ ] SpecKit-compatible structure

---

## Directory Structure

```
.specify/
├── README.md                    # This file
├── ARCHITECTURE.md              # Overall system design
├── DESIGN_SYSTEM.md             # UI/UX guidelines
├── PROTOCOL.md                  # Mostro protocol spec
├── NOSTR_EXCHANGE_RATES.md      # v2 feature: Nostr-based rates
├── v1-reference/                # Flutter v1 implementation docs
│   ├── README.md
│   ├── EXCHANGE_SERVICE.md
│   ├── MOSTRO_SERVICE.md
│   └── ...
├── memory/                      # Spec evolution notes
│   └── constitution.md
├── scripts/                     # Tooling for spec generation
└── templates/                   # Spec templates
```

---

## Roadmap

### Phase 1: Core Features (v2.0)

- [ ] Nostr-based exchange rates
- [ ] Rust core with flutter_rust_bridge 2.x
- [ ] HD key management in Rust
- [ ] Gift wrap (NIP-59) in Rust
- [ ] Order state machine in Rust

### Phase 2: Enhanced Features (v2.1)

- [ ] Multi-Mostro support
- [ ] Advanced dispute resolution
- [ ] Rate history & charting
- [ ] Custom rate providers

### Phase 3: Scaling (v2.2+)

- [ ] Offline order signing
- [ ] Tor integration
- [ ] Multi-currency escrow
- [ ] Decentralized reputation

---

## Questions?

- **Spec clarification:** Open issue in `MostroP2P/app` with `spec:question` label
- **Implementation help:** Ask in `#dev` channel on Mostro Discord
- **Architecture decisions:** Tag `@negrunch` in issue or PR

---

**Last Updated:** 2026-03-25  
**Spec Version:** v2.0-draft
