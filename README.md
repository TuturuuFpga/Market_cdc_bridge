# Market Data CDC Bridge — README

## 1. Architecture Summary

This design implements a low‑latency market data ingress bridge that safely transfers fixed‑width market messages from the `rx_clk` domain into the `core_clk` domain. 
After that, the filterd market messages are transfered form the `core_clk` domain into `downstream_clk` domain.

Clock domain crossing (CDC) is handled using a free and parameterized AXI4-stream Asynchronous FIFO IP (no support for FWFT).

All sub modules are designed to comply with AXI stream standard.

* Normalizing FIFO and other handshake signals to an AXI‑Stream interface provides a standardized ready/valid protocol with well‑defined backpressure behavior. This improves modularity, reuse, and verification by allowing seamless integration with other AXI‑based components and existing verification IP. Functionally, AXI‑Stream preserves the same data transfer semantics as a traditional FIFO while raising the abstraction level and making the design more scalable and production‑ready.

* market_cdc_bridge = wrap of (async fifo -> seq_checker -> async fifo/skid buffer). The top module is created in the block design

* The detail explaination of the architecture is in the "design_doc.docx" document.

---

## 2. Latency Reasoning

### Latency Breakdown (Minimum Path, No Backpressure)
- axi stream fifo_0: 1  clock cycle latency (rx_clk) for data handshake + 2 clock cycles latency (CDC) for gray pointer (core_clk) + 1 clock cycles for generating valid output (core_clk).
- seq_checker (from s_valid to m_valid) 2 core_clk
- axi stream fifo_0: 1 fifo clock latency (core _clk) for data handshake + 2 clock latency (CDC) for gray pointer (downstream_clk domain) + 1 clock cycles for generating valid output (downstream_clk domain).
- Total latency: 8 – 10 clock cycles (rx_clk + core_clk + downstream_clk).
    + fifo_0 = 6.4 + 3.1 x 3 = 15.7 ns
    + seq_checker = 3.1 x 2 = 6.2 ns
    + fifo_1 = 3.1 + 5 x 3 = 18.1 ns
    + total = 40 ns
---

## 3. AI Usage Log
- GitHub Copilot for code alignment only.
---

## Deliverables

| File                     | Description                                      |
|--------------------------|--------------------------------------------------|
| design_docx              | Design specification of the module               |
| async_fifo               | Asynchronous FIFO implementation                 |
| market_cdc_bridge.v      | Sequence validation module                       |
| tb_market_cdc_bridge.sv  | Self‑checking verification testbench             |
| README.md                | Architecture, latency, and AI usage documentation|

---

## Notes
- "Reset during traffic" case is not checked
- "Symbol wraparound" case is not checked
- "FIFO underflow test" case is not checked
- "FIFO overflow test" case is not checked
- Checker module for counters is not created.
- Due to time limited, the candidate used Verilog to design the module.