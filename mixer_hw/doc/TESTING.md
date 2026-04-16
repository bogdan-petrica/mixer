# Testing Approach

## Philosophy

Testing focuses on **verifying behavior**, not achieving arbitrary coverage metrics. The strategy is:

1. **Test each IP sub-block thoroughly** - test all non trivial core algorithms, state machines and interface protocols with high coverage.
2. **Trust structural integrity** - audio mixer IP core top level is simple wiring, no simulation needed, the synthesis tool provides required level of validation
3. **Design for testability** – The audio mixer IP core is split into independent IP sub-blocks that are well defined, contained, and can be tested and validated independently. Examples:
   - [AXI2CTRL & CTRL](./AudioMixerIP.md#axi2ctrl--ctrl)
   - [CORE & DELAY LINE](./AudioMixerIP.md#core--delay_line--delay_mux)

## Why This Approach

Testing at the sub-block level provides confidence at two levels:
- **Correct sub-block behavior** (algorithmic correctness, edge cases)
- **Integration contract** (interface handshaking, data formats)

Verifying both sides of an interface requires more testbench code, but it also **documents and enforces the integration contract**. This approach provides test coverage that far exceeds what could be achieved by testing only at the top IP core level, while keeping test complexity manageable.

**Trade-off:** Thorough sub-block testing means some test cases can only be simulated (not run on hardware). The upside is that future changes or reuse of a sub-block are much safer.

## Summary

This testing strategy prioritizes **where bugs actually hide** (complex logic, interface contracts) over exhaustive but low-value simulation. The design is modular, testable, and the verification effort is focused and defensible.