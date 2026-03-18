# Market Data CDC Bridge — README

## 1. Architecture Summary

This design implements a low‑latency market data ingress bridge that safely transfers fixed‑width market messages from the `rx_clk` domain into the `core_clk` domain. 
After that, the filterd market messages are transfered form the `core_clk` domain into `downstream_clk` domain.

Clock domain crossing (CDC) is handled using a free and parameterized AXI4-stream Asynchronous FIFO IP (no support for FWFT) provide by Xilinx.
All sub modules are designed to comply with AXI stream standard.

* Normalizing FIFO and other handshake signals to an AXI‑Stream interface provides a standardized ready/valid protocol with well‑defined backpressure behavior. This improves modularity, reuse, and verification by allowing seamless integration with other AXI‑based components and existing verification IP. Functionally, AXI‑Stream preserves the same data transfer semantics as a traditional FIFO while raising the abstraction level and making the design more scalable and production‑ready.

* market_cdc_bridge = wrap of (async fifo -> seq_checker -> async fifo/skid buffer). The top module is created in the block design

* he detail explaination of the architecture is in the "design_doc.docx" document.

---

## 2. Latency Reasoning

### Latency Breakdown (Minimum Path, No Backpressure)

seq_checker (from s_valid to m_valid): 2 core_clk cycles
axi stream fifo: High latency due to Xilinx's multi-pipeline design. Although this design results in high latency, it allows the IP to operate at extremely high frequencies. (The latency of this IP is not clearly stated in any Xilinx documentation).
Total latency: axi stream fifo_0 + seq_checker + axi stream fifo_1

---

## 3. AI Usage Log
- GitHub Copilot for code alignment only.
---

## Deliverables

| File                     | Description                                      |
|--------------------------|--------------------------------------------------|
| design_docx              | Design specification of the module               |
| N/A (using IP)           | Asynchronous FIFO implementation                 |
| seq_checker.v            | Sequence validation module                       |
| tb_market_cdc_bridge.sv  | Self‑checking verification testbench             |
| tb_market_cdc_bridge.wcfg| Waveform config for quick checking               |
| README.md                | Architecture, latency, and AI usage documentation|

---

## Notes
- "Reset during traffic" case is not checked
- "Symbol wraparound" case is not checked
- "FIFO underflow test" case is not checked
- "FIFO overflow test" case is not checked
- Checker module for counters is not created.
- Due to time limited, the candidate used Verilog to design the module.

``