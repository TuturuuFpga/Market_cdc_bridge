`timescale 1ns/1ps
 
module axi4_stream_fifo #
    //declare parameters
    (
        parameter integer P_DT_WIDTH                =   64,
        parameter integer P_FIFO_DEPTH              =   16,
        parameter integer P_AD_WIDTH                =   $clog2(P_FIFO_DEPTH)
    )
    //declare inputs/outputs of fifo
    (
        input                           s_axis_clock,
        input                           m_axis_clock,
        input                           reset_n,
        //
        input    [P_DT_WIDTH-1:0]       s_axis_tdata,
        input                           s_axis_tvalid,
        output                          s_axis_tready,
        //
        output   [P_DT_WIDTH-1:0]       m_axis_tdata,
        output                          m_axis_tvalid,
        input                           m_axis_tready
    );
 
    //declare internal signals
    //declare internal signals of synchronizer block (g_rptr_sync is output signal)
    //gray read pointer
    reg     [P_AD_WIDTH:0]          g_rptr;
    //gray read pointer after sync
    reg     [P_AD_WIDTH:0]          g_rptr_sync;
    //temporary read pointer of synchronizer block
    reg     [P_AD_WIDTH:0]          rptr_tmp;
 
    //declare internal signals of synchronizer block (g_wptr_sync is output signal)
    //gray write pointer
    reg     [P_AD_WIDTH:0]          g_wptr;
    //gray write pointer after sync
    reg     [P_AD_WIDTH:0]          g_wptr_sync;
    //temporary write pointer of synchronizer block
    reg     [P_AD_WIDTH:0]          wptr_tmp;
 
    //declare internal signals of wptr_handler block
    wire    [P_AD_WIDTH:0]          full_ptr;
    //handshake condition between slave tvalid and tready
    wire                            wr_con;
    //binary write pointer
    reg     [P_AD_WIDTH:0]          b_wptr;
    //next value of binary write pointer
    wire    [P_AD_WIDTH:0]          b_wptr_next;
    //next value of gray write pointer
    wire    [P_AD_WIDTH:0]          g_wptr_next;
    //full flag
    wire                            full;
 
    //declare internal signals of rptr_handler block
    //signal is used to indicate FIFO empty or not
    wire                            empty;
    //handshake condition between master tvalid and tready
    wire                            rd_con;
    //binary read pointer
    reg     [P_AD_WIDTH:0]          b_rptr;
    //next value of binary read pointer
    wire    [P_AD_WIDTH:0]          b_rptr_next;
    //next value of gray read pointer
    wire    [P_AD_WIDTH:0]          g_rptr_next;
 
    //declare internal signals of fifo_mem block
    //FIFO memory
    reg     [P_DT_WIDTH-1:0]    fifo    [0:P_FIFO_DEPTH-1];
 
    //
    reg                             s_tready;
    reg                             m_tvalid;
    reg     [P_DT_WIDTH-1:0]        dout;
    wire    [P_DT_WIDTH-1:0]        din;
 
    //2-ff for syncchronize gray read pointer into s_axis_clock domain
    always@(posedge s_axis_clock, negedge reset_n) begin
        if(~reset_n) begin
            rptr_tmp        <= 0;
            g_rptr_sync     <= 0;
        end else begin
            rptr_tmp        <=  g_rptr;
            g_rptr_sync     <=  rptr_tmp;
        end
    end
 
 
    //2-ff for syncchronize gray write pointer into m_axis_clock domain
    always@(posedge m_axis_clock, negedge reset_n) begin
        if(~reset_n) begin
            wptr_tmp        <=  0;
            g_wptr_sync     <=  0;
        end else begin
            wptr_tmp        <=  g_wptr;
            g_wptr_sync     <=  wptr_tmp;
        end
    end
 
    ////wptr_handler block
    ///generate binary write pointer
    assign  wr_con          =   s_axis_tvalid & s_tready;
    //Check if there is handshake between tvalid and tready -> write pointer adds value 1.
    assign  b_wptr_next     =   (wr_con) ? (b_wptr + 1) : b_wptr;
    //flip flop to update value of binary write pointer
    always@(posedge s_axis_clock, negedge reset_n) begin
        if(~reset_n) begin
            b_wptr      <=  0;
        end else begin
            b_wptr      <=  b_wptr_next;
        end
    end
    //generate gray write pointer
    //Convert binary write pointer to gray write pointer
    assign  g_wptr_next     =   (b_wptr_next >> 1) ^ (b_wptr_next);
    //flip flop to update value of gray write pointer
    always@(posedge s_axis_clock, negedge reset_n) begin
        if(~reset_n) begin
            g_wptr      <=  0;
        end else begin
            g_wptr      <=  g_wptr_next;
        end
    end
    //generate full flag
    assign  full_ptr        =   {~g_rptr_sync[P_AD_WIDTH:P_AD_WIDTH-1],g_rptr_sync[P_AD_WIDTH-2:0]};
    //Check next logic of full flag
    assign  full           =   {full_ptr == g_wptr_next} ? 1'd1 : 1'd0;
    //flip flop to update logic of s_tready 
    always@(posedge s_axis_clock, negedge reset_n) begin
        if(~reset_n) begin
            s_tready    <=  0;
        end else begin
            s_tready    <=  ~full;
        end
    end
    //generate slave AXI stream ready memory to stream
    assign  s_axis_tready  =   s_tready;
 
    ////rptr_handler block
    ///generate binary read pointer
    //condition to handshake data
    assign  rd_con          =   m_axis_tready & (m_tvalid);
    //Check if there is handshake between tvalid and tready -> read pointer adds value 1.
    assign  b_rptr_next     =   (rd_con) ? (b_rptr + 1) : b_rptr;
    //flip flop to update value of binary read pointer
    always@(posedge m_axis_clock, negedge reset_n) begin
        if(~reset_n) begin
            b_rptr      <=  0;
        end else begin
            b_rptr      <=  b_rptr_next;
        end
    end
    //generate gray read pointer
    //Convert binary read pointer to gray read pointer
    assign  g_rptr_next     =   (b_rptr_next >> 1) ^ (b_rptr_next);
    //flip flop to update value of gray write pointer
    always@(posedge m_axis_clock, negedge reset_n) begin
        if(~reset_n) begin
            g_rptr      <=  0;
        end else begin
            g_rptr      <=  g_rptr_next;
        end
    end
    //generate empty flag
    //Check next logic of empty flag
    assign  empty          =   {g_rptr_next == g_wptr_sync} ? 1'd1 : 1'd0;
    //flip flop to update logic of empty flag
    always@(posedge m_axis_clock, negedge reset_n) begin
        if(~reset_n) begin
            m_tvalid   <=  0;
        end else begin
            m_tvalid   <=  ~empty;
        end
    end
    //generate master AXI stream valid
    assign  m_axis_tvalid   =   m_tvalid;
 
 
    ////fifo_mem block
    ///Write data to memory cell in FIFO
    assign din = s_axis_tdata;
    always @(posedge s_axis_clock) begin
        if(wr_con) begin
            fifo[b_wptr[P_AD_WIDTH-1:0]]     <=  din;
        end
    end
 
    always @(posedge m_axis_clock or negedge reset_n) begin
     if (~reset_n) begin
        dout <= 0;
     end else begin
        dout <= fifo[b_rptr_next[P_AD_WIDTH-1:0]];
     end
    end
    //Read data from memory cell in FIFO
    assign  m_axis_tdata = dout [P_DT_WIDTH-1 : 0];
endmodule
