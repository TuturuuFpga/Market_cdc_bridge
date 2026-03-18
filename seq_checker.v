`timescale 1ns / 1ps
module seq_checker #(
    parameter integer P_DT_WIDTH = 64
)(
    input                           s_axis_clock,
    input                           reset_n,

    input      [P_DT_WIDTH-1:0]     s_axis_tdata,
    input                           s_axis_tvalid,
    output                          s_axis_tready,

    output reg [P_DT_WIDTH-1:0]     m_axis_tdata,
    output reg                      m_axis_tvalid,
    input                           m_axis_tready,

    // counters
    output reg [31:0]               cnt_forwarded,      // Messages successfully forwarded
    output reg [31:0]               cnt_seq_gap,        // Sequence gaps encountered (total missing messages)
    output reg [31:0]               cnt_seq_late,       // Late/duplicate messages dropped
    output reg [31:0]               cnt_unknown_type,   // Messages with invalid msg_type
    output reg [31:0]               cnt_rx_backpressure // Cycles where rx_ready was low 
);

    //==========================================================================
    // 1) Declarations (grouped)
    //==========================================================================

    // expected_seq table (256 x 16)
    reg [15:0] expected_seq [0:255];
    integer i;

    // captured input message (for next-cycle checking)
    reg [63:0] input_message;

    // extracted fields / addressing
    wire [7:0]  msg_type;
    wire [7:0]  rd_addr;
    reg  [7:0]  wr_addr;

    // read / write enables and data
    wire        rd_en;
    wire        wr_en;
    wire [15:0] seq;
    reg  [15:0] check_data;
    reg  [15:0] wr_data;

    // control flags / pipeline
    reg         gap_cond;
    reg         normal_cond;
    reg         msg_vld;
    reg         receive_state;

    // counter of remaining forwarded-but-not-yet-sent data (due to backpressure)
    reg  [1:0]  cnt;

    // (kept as in your code; declared but not used)
    reg         update_data;

    //==========================================================================
    // 2) Continuous assigns
    //==========================================================================

    assign msg_type = s_axis_tdata[63:56];
    assign rd_addr  = s_axis_tdata[55:48];

    // known types: 1 or 2
    assign rd_en = s_axis_tvalid & s_axis_tready & ( (msg_type == 8'd1) | (msg_type == 8'd2) );

    assign seq   = input_message[15:0];
    assign wr_en = gap_cond | normal_cond;

    // input ready follows downstream ready (same as original)
    assign s_axis_tready = m_axis_tready;

    //==========================================================================
    // 3) Initialization
    //==========================================================================

    // initial values inside expected_seq
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            expected_seq[i] = i[15:0];
        end
    end

    //==========================================================================
    // 4) Program body (always blocks)
    //==========================================================================

    // capture data from FIFO for checking at the next clock
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            input_message <= 64'd0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            input_message <= s_axis_tdata;
        end
    end

    // align write address with read address
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            wr_addr <= 8'd0;
        end else begin
            wr_addr <= rd_addr;
        end
    end

    // Read logic: synchronous read of expected_seq
    always @(posedge s_axis_clock) begin
        if (rd_en) begin
            check_data <= expected_seq[rd_addr]; // check_data = expected_seq[symbol_id]
        end
    end

    // Pipeline valid for compare stage
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            msg_vld <= 1'b0;
        end else begin
            msg_vld <= rd_en;
        end
    end

    // gap and normal condition that msg is forwarded
    always @(*) begin
        gap_cond = 1'b0;
        if (seq > check_data) begin
            gap_cond = msg_vld;
        end
    end

    always @(*) begin
        normal_cond = 1'b0;
        if (seq == check_data) begin
            normal_cond = msg_vld;
        end
    end

    // compute write-back expected sequence
    always @(*) begin
        wr_data = 16'd0;
        if (gap_cond) begin
            wr_data = seq + 16'd1;
        end else if (normal_cond) begin
            wr_data = check_data + 16'd1;
        end
    end

    // Write logic: update expected_seq only in Normal and Gap condition
    always @(posedge s_axis_clock) begin
        if (wr_en) begin
            expected_seq[wr_addr] <= wr_data;
        end
    end

    // counter of remain valid data that not sent due to backpressure
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            cnt <= 2'd0;
        end else begin
            cnt <= cnt + (gap_cond || normal_cond) - (m_axis_tvalid && m_axis_tready);
        end
    end

    // receive_state
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            receive_state <= 1'b0;
        end else begin
            receive_state <= s_axis_tready & s_axis_tvalid;
        end
    end

    // m_axis_tvalid generation
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            m_axis_tvalid <= 1'b0;
        end else if (m_axis_tvalid && ~m_axis_tready) begin
            m_axis_tvalid <= m_axis_tvalid; // hold
        end else if (gap_cond || normal_cond) begin
            m_axis_tvalid <= 1'b1;
        end else if (m_axis_tvalid && m_axis_tready && cnt > 2'd1) begin
            m_axis_tvalid <= 1'b1;
        end else if (m_axis_tvalid && m_axis_tready) begin
            m_axis_tvalid <= 1'b0;
        end
    end

    // m_axis_tdata generation
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            m_axis_tdata <= {P_DT_WIDTH{1'b0}};
        end else if (m_axis_tvalid && ~m_axis_tready) begin
            m_axis_tdata <= m_axis_tdata; // hold
        end else if (gap_cond || normal_cond) begin
            m_axis_tdata <= input_message;
        end else if (m_axis_tvalid && m_axis_tready && cnt > 2'd1) begin
            m_axis_tdata <= input_message;
        end
    end

    // counter forward
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            cnt_forwarded <= 32'd0;
        end else if (gap_cond || normal_cond) begin
            cnt_forwarded <= cnt_forwarded + 32'd1;
        end
    end

    // counter seq gap
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            cnt_seq_gap <= 32'd0;
        end else if (gap_cond || normal_cond) begin
            cnt_seq_gap <= cnt_seq_gap + (seq - check_data);
        end
    end

    // counter seq late
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            cnt_seq_late <= 32'd0;
        end else if (receive_state && ~gap_cond && ~normal_cond && msg_vld) begin
            cnt_seq_late <= cnt_seq_late + 32'd1;
        end
    end

    // counter unknown type
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            cnt_unknown_type <= 32'd0;
        end else if (receive_state && ~gap_cond && ~normal_cond && ~msg_vld) begin
            cnt_unknown_type <= cnt_unknown_type + 32'd1;
        end
    end

    // counter rx_backpressure
    always @(posedge s_axis_clock or negedge reset_n) begin
        if (~reset_n) begin
            cnt_rx_backpressure <= 32'd0;
        end else if (m_axis_tvalid && ~m_axis_tready) begin
            cnt_rx_backpressure <= cnt_rx_backpressure + 32'd1;
        end
    end

endmodule