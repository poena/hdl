`timescale 1ns/100ps

module axi_spi_engine #(

        parameter CMD_FIFO_ADDRESS_WIDTH = 4,
        parameter SDO_FIFO_ADDRESS_WIDTH = 5,
        parameter SDI_FIFO_ADDRESS_WIDTH = 5,
        parameter MM_IF_TYPE = 0,
        parameter UP_ADDRESS_WIDTH = 14,
        parameter ASYNC_SPI_CLK = 0,
        parameter NUM_OFFLOAD = 0,
        parameter OFFLOAD0_CMD_MEM_ADDRESS_WIDTH = 4,
        parameter OFFLOAD0_SDO_MEM_ADDRESS_WIDTH = 4,
        parameter ID = 0,
        parameter DATA_WIDTH = 8,
        parameter NUM_OF_SDI = 1 ) (

        // Slave AXI interface

        input         s_axi_aclk,
        input         s_axi_aresetn,
        input         s_axi_awvalid,
        input  [31:0] s_axi_awaddr,
        output        s_axi_awready,
        input   [2:0] s_axi_awprot,
        input         s_axi_wvalid,
        input  [31:0] s_axi_wdata,
        input  [ 3:0] s_axi_wstrb,
        output        s_axi_wready,
        output        s_axi_bvalid,
        output [ 1:0] s_axi_bresp,
        input         s_axi_bready,
        input         s_axi_arvalid,
        input  [31:0] s_axi_araddr,
        output        s_axi_arready,
        input   [2:0] s_axi_arprot,
        output        s_axi_rvalid,
        input         s_axi_rready,
        output [ 1:0] s_axi_rresp,
        output [31:0] s_axi_rdata,

        // up interface

        input                           up_clk,
        input                           up_rstn,
        input                           up_wreq,
        input  [(UP_ADDRESS_WIDTH-1):0] up_waddr,
        input  [31:0]                   up_wdata,
        output                          up_wack,
        input                           up_rreq,
        input  [(UP_ADDRESS_WIDTH-1):0] up_raddr,
        output [31:0]                   up_rdata,
        output                          up_rack,

        output reg irq,

        // SPI signals

        input spi_clk,

        output spi_resetn,

        input cmd_ready,
        output cmd_valid,
        output [15:0] cmd_data,

        input sdo_data_ready,
        output sdo_data_valid,
        output [(DATA_WIDTH-1):0] sdo_data,

        output sdi_data_ready,
        input sdi_data_valid,
        input [(NUM_OF_SDI * DATA_WIDTH-1):0] sdi_data,

        output sync_ready,
        input sync_valid,
        input [7:0] sync_data,

        // Offload ctrl signals

        output offload0_cmd_wr_en,
        output [15:0] offload0_cmd_wr_data,

        output offload0_sdo_wr_en,
        output [(DATA_WIDTH-1):0] offload0_sdo_wr_data,

        output reg offload0_mem_reset,
        output reg offload0_enable,
        input offload0_enabled
);

localparam PCORE_VERSION = 'h010071;
localparam S_AXI = 0;
localparam UP_FIFO = 1;

wire clk;
wire rstn;

wire [CMD_FIFO_ADDRESS_WIDTH:0] cmd_fifo_room;
wire cmd_fifo_almost_empty;

wire [15:0] cmd_fifo_in_data;
wire cmd_fifo_in_ready;
wire cmd_fifo_in_valid;

wire [SDO_FIFO_ADDRESS_WIDTH:0] sdo_fifo_room;
wire sdo_fifo_almost_empty;

wire [(DATA_WIDTH-1):0] sdo_fifo_in_data;
wire sdo_fifo_in_ready;
wire sdo_fifo_in_valid;

wire [SDI_FIFO_ADDRESS_WIDTH:0] sdi_fifo_level;
wire sdi_fifo_almost_full;

wire [(NUM_OF_SDI * DATA_WIDTH-1):0] sdi_fifo_out_data;
wire sdi_fifo_out_ready;
wire sdi_fifo_out_valid;

reg up_sw_reset = 1'b1;
wire up_sw_resetn = ~up_sw_reset;

reg  [31:0]                     up_rdata_ff = 'd0;
reg                             up_wack_ff = 1'b0;
reg                             up_rack_ff = 1'b0;
wire                            up_wreq_s;
wire                            up_rreq_s;
wire [31:0]                     up_wdata_s;
wire [(UP_ADDRESS_WIDTH-1):0]   up_waddr_s;
wire [(UP_ADDRESS_WIDTH-1):0]   up_raddr_s;

// Scratch register
reg [31:0] up_scratch = 'h00;

reg  [7:0] sync_id = 'h00;
reg        sync_id_pending = 1'b0;

generate if (MM_IF_TYPE == S_AXI) begin

  // assign clock and reset

  assign clk = s_axi_aclk;
  assign rstn = s_axi_aresetn;

  // interface wrapper

  up_axi #(
        .ADDRESS_WIDTH (UP_ADDRESS_WIDTH)
  ) i_up_axi (
        .up_rstn(rstn),
        .up_clk(clk),
        .up_axi_awvalid(s_axi_awvalid),
        .up_axi_awaddr(s_axi_awaddr),
        .up_axi_awready(s_axi_awready),
        .up_axi_wvalid(s_axi_wvalid),
        .up_axi_wdata(s_axi_wdata),
        .up_axi_wstrb(s_axi_wstrb),
        .up_axi_wready(s_axi_wready),
        .up_axi_bvalid(s_axi_bvalid),
        .up_axi_bresp(s_axi_bresp),
        .up_axi_bready(s_axi_bready),
        .up_axi_arvalid(s_axi_arvalid),
        .up_axi_araddr(s_axi_araddr),
        .up_axi_arready(s_axi_arready),
        .up_axi_rvalid(s_axi_rvalid),
        .up_axi_rresp(s_axi_rresp),
        .up_axi_rdata(s_axi_rdata),
        .up_axi_rready(s_axi_rready),
        .up_wreq(up_wreq_s),
        .up_waddr(up_waddr_s),
        .up_wdata(up_wdata_s),
        .up_wack(up_wack_ff),
        .up_rreq(up_rreq_s),
        .up_raddr(up_raddr_s),
        .up_rdata(up_rdata_ff),
        .up_rack(up_rack_ff)
  );

  assign up_rdata = 32'b0;
  assign up_rack = 1'b0;
  assign up_wack = 1'b0;

end
endgenerate

generate if (MM_IF_TYPE == UP_FIFO) begin

  // assign clock and reset

  assign clk = up_clk;
  assign rstn = up_rstn;

  assign up_wreq_s = up_wreq;
  assign up_waddr_s = up_waddr;
  assign up_wdata_s = up_wdata;
  assign up_wack = up_wack_ff;
  assign up_rreq_s = up_rreq;
  assign up_raddr_s = up_raddr;
  assign up_rdata = up_rdata_ff;
  assign up_rack = up_rack_ff;

end
endgenerate



// IRQ handling
reg [3:0] up_irq_mask = 'h0;
wire [3:0] up_irq_source;
wire [3:0] up_irq_pending;

assign up_irq_source = {
        sync_id_pending,
        sdi_fifo_almost_full,
        sdo_fifo_almost_empty,
        cmd_fifo_almost_empty
};

assign up_irq_pending = up_irq_mask & up_irq_source;

always @(posedge clk) begin
        if (rstn == 1'b0)
                irq <= 1'b0;
        else
                irq <= |up_irq_pending;
end

always @(posedge clk) begin
        if (rstn == 1'b0) begin
                up_wack_ff <= 1'b0;
                up_scratch <= 'h00;
                up_sw_reset <= 1'b1;
                up_irq_mask <= 'h00;
                offload0_enable <= 1'b0;
                offload0_mem_reset <= 1'b0;
        end else begin
                up_wack_ff <= up_wreq_s;
                offload0_mem_reset <= 1'b0;
                if (up_wreq_s) begin
                        case (up_waddr_s)
                        8'h02: up_scratch <= up_wdata_s;
                        8'h10: up_sw_reset <= up_wdata_s;
                        8'h20: up_irq_mask <= up_wdata_s;
                        8'h40: offload0_enable <= up_wdata_s[0];
                        8'h42: offload0_mem_reset <= up_wdata_s[0];
                        endcase
                end
        end
end

always @(posedge clk) begin
        if (rstn == 1'b0) begin
                up_rack_ff <= 'd0;
        end else begin
                up_rack_ff <= up_rreq_s;
        end
end

always @(posedge clk) begin
        case (up_raddr_s)
        8'h00: up_rdata_ff <= PCORE_VERSION;
        8'h01: up_rdata_ff <= ID;
        8'h02: up_rdata_ff <= up_scratch;
        8'h03: up_rdata_ff <= DATA_WIDTH;
        8'h10: up_rdata_ff <= up_sw_reset;
        8'h20: up_rdata_ff <= up_irq_mask;
        8'h21: up_rdata_ff <= up_irq_pending;
        8'h22: up_rdata_ff <= up_irq_source;
        8'h30: up_rdata_ff <= sync_id;
        8'h34: up_rdata_ff <= cmd_fifo_room;
        8'h35: up_rdata_ff <= sdo_fifo_room;
        8'h36: up_rdata_ff <= sdi_fifo_level;
        8'h3a: up_rdata_ff <= sdi_fifo_out_data;
        8'h3c: up_rdata_ff <= sdi_fifo_out_data; /* PEEK register */
        8'h40: up_rdata_ff <= {offload0_enable};
        8'h41: up_rdata_ff <= {offload0_enabled};
        default: up_rdata_ff <= 'h00;
        endcase
end

always @(posedge clk) begin
        if (up_sw_resetn == 1'b0) begin
                sync_id <= 'h00;
                sync_id_pending <= 1'b0;
        end else begin
                if (sync_valid == 1'b1) begin
                        sync_id <= sync_data;
                        sync_id_pending <= 1'b1;
                end else if (up_wreq_s == 1'b1 && up_waddr_s == 8'h21 && up_wdata_s[3] == 1'b1) begin
                        sync_id_pending <= 1'b0;
                end
        end
end

assign sync_ready = 1'b1;

generate if (ASYNC_SPI_CLK) begin

wire spi_reset;
ad_rst i_spi_resetn (
        .preset(up_sw_reset),
        .clk(spi_clk),
        .rst(spi_reset)
);
assign spi_resetn = ~spi_reset;
end else begin
assign spi_resetn = ~up_sw_reset;
end
endgenerate

/* Evaluates to true if FIFO level/room is 3/4 or above */
`define axi_spi_engine_check_watermark(x, n) \
        (x[n] == 1'b1 || x[n-1:n-2] == 2'b11)

assign cmd_fifo_in_valid = up_wreq_s == 1'b1 && up_waddr_s == 8'h38;
assign cmd_fifo_in_data = up_wdata_s[15:0];
assign cmd_fifo_almost_empty =
        `axi_spi_engine_check_watermark(cmd_fifo_room, CMD_FIFO_ADDRESS_WIDTH);

util_axis_fifo #(
        .DATA_WIDTH(16),
        .ASYNC_CLK(ASYNC_SPI_CLK),
        .ADDRESS_WIDTH(CMD_FIFO_ADDRESS_WIDTH),
        .S_AXIS_REGISTERED(0)
) i_cmd_fifo (
        .s_axis_aclk(clk),
        .s_axis_aresetn(up_sw_resetn),
        .s_axis_ready(cmd_fifo_in_ready),
        .s_axis_valid(cmd_fifo_in_valid),
        .s_axis_data(cmd_fifo_in_data),
        .s_axis_room(cmd_fifo_room),

        .m_axis_aclk(spi_clk),
        .m_axis_aresetn(spi_resetn),
        .m_axis_ready(cmd_ready),
        .m_axis_valid(cmd_valid),
        .m_axis_data(cmd_data)
);

assign sdo_fifo_in_valid = up_wreq_s == 1'b1 && up_waddr_s == 8'h39;
assign sdo_fifo_in_data = up_wdata_s[(DATA_WIDTH-1):0];
assign sdo_fifo_almost_empty =
        `axi_spi_engine_check_watermark(sdo_fifo_room, SDO_FIFO_ADDRESS_WIDTH);

util_axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ASYNC_CLK(ASYNC_SPI_CLK),
        .ADDRESS_WIDTH(SDO_FIFO_ADDRESS_WIDTH),
        .S_AXIS_REGISTERED(0)
) i_sdo_fifo (
        .s_axis_aclk(clk),
        .s_axis_aresetn(up_sw_resetn),
        .s_axis_ready(sdo_fifo_in_ready),
        .s_axis_valid(sdo_fifo_in_valid),
        .s_axis_data(sdo_fifo_in_data),
        .s_axis_room(sdo_fifo_room),

        .m_axis_aclk(spi_clk),
        .m_axis_aresetn(spi_resetn),
        .m_axis_ready(sdo_data_ready),
        .m_axis_valid(sdo_data_valid),
        .m_axis_data(sdo_data)
);

assign sdi_fifo_out_ready = up_rreq_s == 1'b1 && up_raddr_s == 8'h3a;
assign sdi_fifo_almost_full =
        `axi_spi_engine_check_watermark(sdi_fifo_level, SDI_FIFO_ADDRESS_WIDTH);

util_axis_fifo #(
        .DATA_WIDTH(NUM_OF_SDI * DATA_WIDTH),
        .ASYNC_CLK(ASYNC_SPI_CLK),
        .ADDRESS_WIDTH(SDI_FIFO_ADDRESS_WIDTH),
        .S_AXIS_REGISTERED(0)
) i_sdi_fifo (
        .s_axis_aclk(spi_clk),
        .s_axis_aresetn(spi_resetn),
        .s_axis_ready(sdi_data_ready),
        .s_axis_valid(sdi_data_valid),
        .s_axis_data(sdi_data),

        .m_axis_aclk(clk),
        .m_axis_aresetn(up_sw_resetn),
        .m_axis_ready(sdi_fifo_out_ready),
        .m_axis_valid(sdi_fifo_out_valid),
        .m_axis_data(sdi_fifo_out_data),
        .m_axis_level(sdi_fifo_level)
);

assign offload0_cmd_wr_en = up_wreq_s == 1'b1 && up_waddr_s == 8'h44;
assign offload0_cmd_wr_data = up_wdata_s[15:0];

assign offload0_sdo_wr_en = up_wreq_s == 1'b1 && up_waddr_s == 8'h45;
assign offload0_sdo_wr_data = up_wdata_s[7:0];

endmodule
