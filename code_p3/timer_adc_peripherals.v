`timescale 1ns / 1ps

// =====================================================================
// 1. MODULE WRAPPER: timer_adc8_cpu_if
// =====================================================================
module timer_adc8_cpu_if (
    input wire clk, rst_n, cs, we,
    input wire [3:0] addr,
    input wire [7:0] wdata,
    output wire [7:0] rdata,
    output wire irq,
    output wire adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input wire adc_cmp,
    output wire pwm_out,
    output wire [7:0] dbg_tmr_cnt // <--- THÊM MỚI: Cổng đẩy Timer Cnt ra
);
    timer_adc8_top u_periph (
        .clk(clk), .rst_n(rst_n), .cs(cs), .we(we),
        .addr(addr), .wdata(wdata), .rdata(rdata),
        .irq(irq), .adc_sample(adc_sample), .adc_ch(adc_ch),
        .adc_dac(adc_dac), .adc_cmp(adc_cmp), .pwm_out(pwm_out),
        .dbg_tmr_cnt(dbg_tmr_cnt) // <--- Nối dây
    );
endmodule

// =====================================================================
// 2. MODULE TOP: timer_adc8_top
// =====================================================================
module timer_adc8_top (
    input clk, rst_n, cs, we,
    input [3:0] addr, input [7:0] wdata,
    output [7:0] rdata, output irq,
    output adc_sample, output [1:0] adc_ch, output [7:0] adc_dac,
    input adc_cmp, output pwm_out,
    output [7:0] dbg_tmr_cnt // <--- THÊM MỚI
);
    wire [7:0] tmr_ctrl, tmr_presc, tmr_load, tmr_cmp_val, tmr_cnt;
    wire [7:0] adc_ctrl, adc_smp, adc_div, adc_thr_lo, adc_thr_hi;
    wire [7:0] irq_en, irq_stat;
    wire tmr_tick, tmr_cmp_pulse, clr_tmr_en;
    wire adc_start_trig, adc_eoc, adc_busy;
    wire [7:0] adc_result;
    
    wire fifo_push = adc_eoc;
    wire fifo_pop; 
    wire fifo_empty, fifo_full, fifo_ovr;
    wire [3:0] fifo_level;
    wire trig_miss = adc_busy && ((adc_ctrl[3:2] == 2'b00 && adc_ctrl[1]) ||
                                      (adc_ctrl[3:2] == 2'b01 && tmr_tick) ||
                                      (adc_ctrl[3:2] == 2'b10 && tmr_cmp_pulse));
    wire [9:0] fifo_wdata = {adc_ctrl[5:4], adc_result};
    wire [9:0] fifo_rdata;

    // GÁN TRỰC TIẾP GIÁ TRỊ ĐẾM RA CỔNG OUTPUT
    assign dbg_tmr_cnt = tmr_cnt; 

    assign adc_start_trig = (adc_ctrl[3:2] == 2'b00) ? 1'b0 :
                            (adc_ctrl[3:2] == 2'b01) ? tmr_tick :
                            (adc_ctrl[3:2] == 2'b10) ? tmr_cmp_pulse : 
                            (adc_ctrl[3:2] == 2'b11) ? 1'b1 : 1'b0;

    timer8 u_timer (
        .clk(clk), .rst_n(rst_n), .en(tmr_ctrl[0]), .oneshot(tmr_ctrl[1]),
        .presc(tmr_presc), .load(tmr_load), .cmp_val(tmr_cmp_val),
        .cnt(tmr_cnt), .tick(tmr_tick), .cmp_pulse(tmr_cmp_pulse),
        .pwm_out(pwm_out), .clr_en(clr_tmr_en)
    );

    sar_adc_ctrl u_adc (
        .clk(clk), .rst_n(rst_n), .en(adc_ctrl[0]),
        .start_trig(adc_start_trig), .sw_start(adc_ctrl[1]),
        .smp(adc_smp), .div(adc_div), .ch_in(adc_ctrl[5:4]),
        .sample(adc_sample), .dac(adc_dac), .ch_out(adc_ch),
        .cmp(adc_cmp), .eoc(adc_eoc), .busy(adc_busy), .result(adc_result)
    );

    sync_fifo u_fifo (
        .clk(clk), .rst_n(rst_n), .push(fifo_push), .pop(fifo_pop),
        .wdata(fifo_wdata), .rdata(fifo_rdata),
        .empty(fifo_empty), .full(fifo_full), .overflow(fifo_ovr), .level(fifo_level)
    );

    apb_regs8 u_regs (
        .clk(clk), .rst_n(rst_n), .cs(cs), .we(we),
        .addr(addr), .wdata(wdata), .rdata(rdata),
        .tmr_ctrl(tmr_ctrl), .tmr_presc(tmr_presc), .tmr_load(tmr_load), .tmr_cmp(tmr_cmp_val), .tmr_cnt(tmr_cnt),
        .adc_ctrl(adc_ctrl), .adc_smp(adc_smp), .adc_div(adc_div), .adc_thr_lo(adc_thr_lo), .adc_thr_hi(adc_thr_hi),
        .fifo_rdata(fifo_rdata), .fifo_empty(fifo_empty), .fifo_full(fifo_full), .fifo_pop(fifo_pop), .fifo_level(fifo_level),
        .adc_busy(adc_busy), .adc_eoc(adc_eoc), .adc_result(adc_result),
        .tmr_tick(tmr_tick), .tmr_cmp_pulse(tmr_cmp_pulse), .clr_tmr_en(clr_tmr_en), .fifo_ovr(fifo_ovr), .trig_miss(trig_miss),
        .irq(irq)
    );
endmodule

// =====================================================================
// MODULE TIMER, ADC, FIFO, REGS GIỮ NGUYÊN (Để tránh lỗi thiếu file)
// =====================================================================
module timer8(input clk, rst_n, en, oneshot, input [7:0] presc, load, cmp_val, output reg [7:0] cnt, output reg tick, cmp_pulse, pwm_out, clr_en);
    reg [7:0] pre;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cnt <= 0; pre <= 0; tick <= 0; cmp_pulse <= 0; pwm_out <= 0; clr_en <= 0; end 
        else if (en) begin tick <= 0; cmp_pulse <= 0; clr_en <= 0;
            if (pre == presc) begin pre <= 0;
                if (cnt == load) begin cnt <= 0; tick <= 1; if (oneshot) clr_en <= 1; end else cnt <= cnt + 1;
                if (cnt == cmp_val) cmp_pulse <= 1; end else pre <= pre + 1;
            pwm_out <= (cnt < cmp_val);
        end else begin cnt <= 0; pre <= 0; pwm_out <= 0; clr_en <= 0; tick <= 0; cmp_pulse <= 0; end
    end
endmodule

module sar_adc_ctrl(input clk, rst_n, en, start_trig, sw_start, input [7:0] smp, div, input [1:0] ch_in, output reg sample, output reg [7:0] dac, output reg [1:0] ch_out, input cmp, output reg eoc, busy, output reg [7:0] result);
    reg [1:0] state; reg [7:0] clk_div, tick_cnt; reg [3:0] bit_idx;
    wire step = (clk_div == div); wire do_start = (start_trig || sw_start) && (state == 0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state <= 0; busy <= 0; sample <= 0; eoc <= 0; dac <= 0; result <= 0; clk_div <= 0; tick_cnt <= 0; bit_idx <= 0; ch_out <= 0; end 
        else if (!en) begin state <= 0; busy <= 0; sample <= 0; eoc <= 0; end 
        else begin eoc <= 0;
            if (do_start) begin state <= 1; busy <= 1; sample <= 1; tick_cnt <= 0; clk_div <= 0; ch_out <= ch_in; end 
            else if (state != 0 && step) begin clk_div <= 0;
                case (state)
                    1: begin if (tick_cnt == smp) begin state <= 2; sample <= 0; bit_idx <= 7; dac <= 8'h80; end else tick_cnt <= tick_cnt + 1; end
                    2: begin dac[bit_idx] <= cmp; if (bit_idx == 0) state <= 3; else begin bit_idx <= bit_idx - 1; dac[bit_idx - 1] <= 1'b1; end end
                    3: begin result <= dac; eoc <= 1; busy <= 0; state <= 0; end
                endcase
            end else clk_div <= clk_div + 1;
        end
    end
endmodule

module sync_fifo(input clk, rst_n, push, pop, input [9:0] wdata, output [9:0] rdata, output empty, full, output [3:0] level, output reg overflow);
    reg [9:0] mem [0:7]; reg [2:0] wptr, rptr; reg [3:0] count;
    assign empty = (count == 0); assign full = (count == 8); assign level = count; assign rdata = empty ? 10'd0 : mem[rptr];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin wptr <= 0; rptr <= 0; count <= 0; overflow <= 0; end else begin overflow <= 0;
            case ({push, pop})
                2'b10: begin if (!full) begin mem[wptr] <= wdata; wptr <= wptr + 1; count <= count + 1; end else overflow <= 1; end
                2'b01: begin if (!empty) begin rptr <= rptr + 1; count <= count - 1; end end
                2'b11: begin
                    if (empty) begin mem[wptr] <= wdata; wptr <= wptr + 1; count <= 1; end
                    else begin mem[wptr] <= wdata; wptr <= wptr + 1; rptr <= rptr + 1; end
                end
            endcase
        end
    end
endmodule

module apb_regs8(input clk, rst_n, cs, we, input [3:0] addr, input [7:0] wdata, output reg [7:0] rdata, output reg [7:0] tmr_ctrl, tmr_presc, tmr_load, tmr_cmp, input [7:0] tmr_cnt, output reg [7:0] adc_ctrl, adc_smp, adc_div, adc_thr_lo, adc_thr_hi, input [9:0] fifo_rdata, input fifo_empty, fifo_full, input [3:0] fifo_level, output reg fifo_pop, input adc_busy, adc_eoc, input [7:0] adc_result, input tmr_tick, tmr_cmp_pulse, clr_tmr_en, fifo_ovr, trig_miss, output irq);
    reg [7:0] irq_en, irq_stat; wire adc_wd = adc_eoc && (adc_result < adc_thr_lo || adc_result > adc_thr_hi); assign irq = |(irq_stat & irq_en);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin tmr_ctrl <= 0; tmr_presc <= 0; tmr_load <= 8'hFF; tmr_cmp <= 8'h80; adc_ctrl <= 0; adc_smp <= 8'h04; adc_div <= 0; adc_thr_lo <= 0; adc_thr_hi <= 8'hFF; irq_en <= 0; irq_stat <= 0; end 
        else begin adc_ctrl[1] <= 0; if (clr_tmr_en) tmr_ctrl[0] <= 0;
            if (cs && we) begin case (addr) 4'h0: tmr_ctrl <= wdata; 4'h1: tmr_presc <= wdata; 4'h2: tmr_load <= wdata; 4'h3: tmr_cmp <= wdata; 4'h5: adc_ctrl <= wdata; 4'h6: adc_smp <= wdata; 4'h7: adc_div <= wdata; 4'h8: adc_thr_lo <= wdata; 4'h9: adc_thr_hi <= wdata; 4'hD: irq_en <= wdata; 4'hE: irq_stat <= irq_stat & ~wdata; endcase end
            if (tmr_tick) irq_stat[0] <= 1; if (tmr_cmp_pulse) irq_stat[1] <= 1; if (adc_eoc) irq_stat[2] <= 1; if (adc_wd) irq_stat[3] <= 1; if (fifo_ovr) irq_stat[4] <= 1; if (trig_miss) irq_stat[5] <= 1;
        end
    end
    always @(*) begin fifo_pop = 0; rdata = 8'h00;
        if (cs && !we) begin case (addr) 4'h0: rdata = tmr_ctrl; 4'h1: rdata = tmr_presc; 4'h2: rdata = tmr_load; 4'h3: rdata = tmr_cmp; 4'h4: rdata = tmr_cnt; 4'h5: rdata = adc_ctrl; 4'h6: rdata = adc_smp; 4'h7: rdata = adc_div; 4'h8: rdata = adc_thr_lo; 4'h9: rdata = adc_thr_hi; 4'hA: begin rdata = fifo_rdata[7:0]; fifo_pop = 1; end 4'hB: rdata = {!fifo_empty, 5'd0, fifo_rdata[9:8]}; 4'hC: rdata = {1'b0, adc_busy, fifo_full, fifo_empty, fifo_level}; 4'hD: rdata = irq_en; 4'hE: rdata = irq_stat; 4'hF: rdata = 8'hA8; endcase end
    end
endmodule