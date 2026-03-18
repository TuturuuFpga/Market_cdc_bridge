`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// AXI4-Stream VIP packages
//////////////////////////////////////////////////////////////////////////////////
import axi4stream_vip_pkg::*;
import design_1_axi4stream_vip_0_0_pkg::*;
import design_1_axi4stream_vip_0_1_pkg::*;

module axi4_stream_FIFO_tb ();

//////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
//////////////////////////////////////////////////////////////////////////////////
parameter integer P_DT_WIDTH  = 64;
parameter integer NUM_DATA_IN = 64;

//////////////////////////////////////////////////////////////////////////////////
// CLOCK & RESET
//////////////////////////////////////////////////////////////////////////////////
bit aclk_322;
bit aclk_156;
bit aclk_200;
bit reset_n;

//////////////////////////////////////////////////////////////////////////////////
// AXI4-STREAM INTERFACE SIGNALS
//////////////////////////////////////////////////////////////////////////////////
logic [P_DT_WIDTH-1:0] m_axis_tdata;
logic                  m_axis_tvalid;
logic                  m_axis_tready;

logic [P_DT_WIDTH-1:0] s_axis_tdata;
logic                  s_axis_tvalid;
logic                  s_axis_tready;

//////////////////////////////////////////////////////////////////////////////////
// CONNECT INTERNAL DUT SIGNALS
//////////////////////////////////////////////////////////////////////////////////
assign m_axis_tdata  = DUT.design_1_i.market_cdc_bridge.seq_checker_0.inst.m_axis_tdata;
assign m_axis_tready = DUT.design_1_i.market_cdc_bridge.seq_checker_0.inst.m_axis_tready;
assign m_axis_tvalid = DUT.design_1_i.market_cdc_bridge.seq_checker_0.inst.m_axis_tvalid;

assign s_axis_tdata  = DUT.design_1_i.market_cdc_bridge.seq_checker_0.inst.s_axis_tdata;
assign s_axis_tready = DUT.design_1_i.market_cdc_bridge.seq_checker_0.inst.s_axis_tready;
assign s_axis_tvalid = DUT.design_1_i.market_cdc_bridge.seq_checker_0.inst.s_axis_tvalid;

//////////////////////////////////////////////////////////////////////////////////
// VERBOSITY CONFIGURATION
// 0   : no log
// 400 : full debug log
//////////////////////////////////////////////////////////////////////////////////
xil_axi4stream_uint slv_axis_verbosity = 400;
xil_axi4stream_uint mst_axis_verbosity = 400;

//////////////////////////////////////////////////////////////////////////////////
// DUT INSTANTIATION
//////////////////////////////////////////////////////////////////////////////////
design_1_wrapper DUT (
    .aclk_322 (aclk_322),
    .aclk_156 (aclk_156),
    .aclk_200 (aclk_200),
    .reset_n  (reset_n)
);

//////////////////////////////////////////////////////////////////////////////////
// VIP AGENTS
//////////////////////////////////////////////////////////////////////////////////
design_1_axi4stream_vip_0_1_slv_t slv_axis_agent;
design_1_axi4stream_vip_0_0_mst_t mst_axis_agent;

//////////////////////////////////////////////////////////////////////////////////
// TASK: START SLAVE VIP
//////////////////////////////////////////////////////////////////////////////////
task start_axis_slave();
    slv_axis_agent = new(
        "Initialize the AXI stream slave vip agent",
        DUT.design_1_i.axi4stream_vip_1.inst.IF
    );

    // Avoid false assertion when bus is idle
    slv_axis_agent.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);

    slv_axis_agent.set_verbosity(slv_axis_verbosity);
    slv_axis_agent.start_slave();
endtask

//////////////////////////////////////////////////////////////////////////////////
// TASK: START MASTER VIP
//////////////////////////////////////////////////////////////////////////////////
task start_axis_master();
    mst_axis_agent = new(
        "Initialize the AXI master vip agent",
        DUT.design_1_i.axi4stream_vip_0.inst.IF
    );

    // Avoid false assertion when bus is idle
    mst_axis_agent.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);

    mst_axis_agent.set_verbosity(mst_axis_verbosity);
    mst_axis_agent.start_master();
endtask

//////////////////////////////////////////////////////////////////////////////////
// READY GENERATION
//////////////////////////////////////////////////////////////////////////////////
task slv_gen_tready_rand();
    axi4stream_ready_gen ready_gen_0;

    ready_gen_0 = slv_axis_agent.driver.create_ready("ready_gen_0");
    ready_gen_0.set_ready_policy(XIL_AXI4STREAM_READY_GEN_RANDOM);
    ready_gen_0.set_low_time_range(0, 8);
    ready_gen_0.set_high_time_range(1, 16);
endtask

task slv_gen_tready_no_backpressure();
    axi4stream_ready_gen ready_gen_1;

    ready_gen_1 = slv_axis_agent.driver.create_ready("ready_gen_1");
    ready_gen_1.set_ready_policy(XIL_AXI4STREAM_READY_GEN_NO_BACKPRESSURE);

    slv_axis_agent.driver.send_tready(ready_gen_1);
endtask

//////////////////////////////////////////////////////////////////////////////////
// CLOCK GENERATION
//////////////////////////////////////////////////////////////////////////////////
initial begin
    aclk_200 = 0;
    forever #2.5 aclk_200 = ~aclk_200;
end

initial begin
    aclk_322 = 0;
    forever #1.5 aclk_322 = ~aclk_322;
end

initial begin
    aclk_156 = 0;
    forever #3.2 aclk_156 = ~aclk_156;
end

//////////////////////////////////////////////////////////////////////////////////
// RESET GENERATION
//////////////////////////////////////////////////////////////////////////////////
bit reset_flag;

initial begin
    reset_n = 0;
    #500ns;
    reset_n = 1;
end

//////////////////////////////////////////////////////////////////////////////////
// START VIPs
//////////////////////////////////////////////////////////////////////////////////
initial begin
    fork
        start_axis_master();
        start_axis_slave();
    join
end

//////////////////////////////////////////////////////////////////////////////////
// MASTER TRANSACTION
//////////////////////////////////////////////////////////////////////////////////
axi4stream_transaction wr_transaction;

initial begin
    wr_transaction = mst_axis_agent.driver.create_transaction(
        "Master VIP write transaction"
    );
    WR_TRANSACTION_FAIL: assert(wr_transaction.randomize());
end

//////////////////////////////////////////////////////////////////////////////////
// DATA GENERATION
//////////////////////////////////////////////////////////////////////////////////
initial begin
    wait (reset_n == 1'b1);

    //Change ready policy here (ready can be no back pressure and random)
    slv_gen_tready_no_backpressure();
    #10ns;

    $display("Start writing data from AXIS master VIP to FIFO");

    for (int i = 0; i < NUM_DATA_IN; i++) begin
        xil_axi4stream_uint      valid_delay;
        xil_axi4stream_data_beat tdata;

        valid_delay = 0;

        //Config message format
        tdata[15:0]  = $urandom(); //seq
        tdata[31:16] = $urandom(); //qty
        tdata[47:32] = $urandom(); //price
        tdata[55:48] = $urandom(); //symbol_id
        tdata[63:56] = $urandom_range(1, 3); //msg_type

        wr_transaction.set_data_beat(tdata);
        wr_transaction.set_delay(valid_delay);

        mst_axis_agent.driver.send(wr_transaction);
    end

    #2000ns;
    $display("AXI stream master completes writing");
    $finish;
end

//////////////////////////////////////////////////////////////////////////////////
// CHECKER LOGIC
//////////////////////////////////////////////////////////////////////////////////

// Queue & expected data
logic [63:0] data_q[$];
logic [63:0] expected_data;

// Extract fields
logic [7:0]  msg_type;
logic [7:0]  symbol_id;
logic [15:0] seq;

// Expected sequence table
logic [15:0] expected_seq [0:255];

assign msg_type     = s_axis_tdata[63:56];
assign symbol_id    = s_axis_tdata[55:48];
assign seq          = s_axis_tdata[15:0];
assign expected_seq = DUT.design_1_i.market_cdc_bridge.seq_checker_0.inst.expected_seq;

//////////////////////////////////////////////////////////////////////////////////
// PUSH VALID DATA INTO QUEUE
//////////////////////////////////////////////////////////////////////////////////
initial begin
    data_q = {};

    forever begin
        @(posedge aclk_322);

        if (!reset_n) begin
            data_q.delete();
        end
        else if (s_axis_tvalid && s_axis_tready &&
                 (msg_type == 1 || msg_type == 2) &&
                 (seq >= expected_seq[symbol_id])) begin
            data_q.push_back(s_axis_tdata);
        end
    end
end

//////////////////////////////////////////////////////////////////////////////////
// COUNT RECEIVED BEATS
//////////////////////////////////////////////////////////////////////////////////
logic [31:0] beat_cnt;

initial begin
    forever begin
        @(posedge aclk_322);

        if (!reset_n) begin
            beat_cnt = 0;
        end
        else if (s_axis_tvalid && s_axis_tready) begin
            beat_cnt = beat_cnt + 1;
        end
    end
end

//////////////////////////////////////////////////////////////////////////////////
// OUTPUT DATA CHECKER
//////////////////////////////////////////////////////////////////////////////////
initial begin
    forever begin
        @(posedge aclk_322);

        if (!reset_n) begin
            // do nothing
        end
        else if (m_axis_tvalid && m_axis_tready) begin
            if (data_q.size() == 0) begin
                $error("Queue underflow at time %0t", $time);
            end
            else begin
                expected_data = data_q.pop_front();

                if (expected_data !== m_axis_tdata) begin
                    $error("Mismatch at %0t: expected=%h actual=%h",
                           $time, expected_data, m_axis_tdata);
                end
            end
        end
    end
end

endmodule