`timescale 1ns / 1ps
module risc8_soc (
    input  wire       clk,
    input  wire       rst,
    output wire       halted,
    output wire [7:0] pc_out,
    output wire       irq,
    output wire       pwm_out,
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp,
    output wire [7:0] soc_tmr_cnt // <--- THÊM PORT NÀY ĐỂ KÉO CNT RA
);

    wire       io_cs;
    wire       io_we;
    wire [3:0] io_addr;
    wire [7:0] io_wdata;
    wire [7:0] io_rdata;
    wire [1:0] flags_out;
    wire       instr_done;

    
risc8_5stage_core #(
    .IO_ENABLE (1),
    .IO_PAGE   (4'hF)
) u_cpu (
    .clk        (clk),
    .rst        (rst),
    .halted     (halted),
    .pc_out     (pc_out),
    .flags_out  (flags_out),
    .instr_done (instr_done),
    .io_cs      (io_cs),
    .io_we      (io_we),
    .io_addr    (io_addr),
    .io_wdata   (io_wdata),
    .io_rdata   (io_rdata)
);


    timer_adc8_cpu_if u_periph (
        .clk        (clk),
        .rst_n      (~rst), 
        .cs         (io_cs),
        .we         (io_we),
        .addr       (io_addr),
        .wdata      (io_wdata),
        .rdata      (io_rdata),
        .irq        (irq),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp),
        .pwm_out    (pwm_out),
        .dbg_tmr_cnt(soc_tmr_cnt) // <--- NHẬN VÀ CHUYỂN TIẾP TÍN HIỆU
    );

endmodule