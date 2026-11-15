`timescale 1ns / 1ps
// P3 self-checking system test, no UVM required for this integration demonstration.
// Uses the exact instance names in the provided risc8_soc.v.
module tb_risc8_soc;
    reg clk = 1'b0;
    reg rst = 1'b1;
    wire halted, irq, pwm_out, adc_sample, adc_cmp;
    wire [7:0] pc_out, adc_dac, top_timer_cnt;
    wire [1:0] adc_ch;

    risc8_soc u_dut (
        .clk(clk), .rst(rst), .halted(halted), .pc_out(pc_out),
        .irq(irq), .pwm_out(pwm_out), .adc_sample(adc_sample),
        .adc_ch(adc_ch), .adc_dac(adc_dac), .adc_cmp(adc_cmp),
        .soc_tmr_cnt(top_timer_cnt)
    );
    afe_model u_afe (
        .sample(adc_sample), .ch(adc_ch), .dac(adc_dac), .cmp(adc_cmp)
    );
    always #5 clk = ~clk; // 100 MHz

    integer checks = 0;
    integer failures = 0;
    integer io_writes = 0;
    integer io_reads = 0;
    reg saw_id = 0;
    reg saw_rch = 0;
    reg saw_data = 0;
    reg saw_stat = 0;
    reg saw_sample = 0;
    reg saw_eoc = 0;
    reg saw_irq = 0;
    reg saw_irq_cleared = 0;
    reg saw_timer_advance = 0;
    reg saw_pwm_high = 0;
    reg saw_pwm_low = 0;
    reg timer_started = 0;
    reg [7:0] last_cnt = 0;

    // Observe settled combinational bus values half a cycle after clock edge.
    always @(negedge clk) begin
        if (!rst) begin
            if (u_dut.io_cs) begin
                $display("IO t=%0t PC=%h we=%b addr=F%h wdata=%h rdata=%h",
                    $time, pc_out, u_dut.io_we, u_dut.io_addr,
                    u_dut.io_wdata, u_dut.io_rdata);
                if (u_dut.io_we) io_writes = io_writes + 1;
                else begin
                    io_reads = io_reads + 1;
                    case (u_dut.io_addr)
                        4'hF: if (u_dut.io_rdata === 8'hA8) saw_id = 1;
                        4'hB: if (u_dut.io_rdata === 8'h81) saw_rch = 1;
                        4'hA: if (u_dut.io_rdata === 8'h56) saw_data = 1;
                        4'hC: if (u_dut.io_rdata === 8'h10) saw_stat = 1;
                    endcase
                end
            end
            if (adc_sample) saw_sample = 1;
            if (u_dut.u_periph.u_periph.adc_eoc) saw_eoc = 1;
            if (irq) saw_irq = 1;
            if (saw_irq && !irq) saw_irq_cleared = 1;
            if (u_dut.u_periph.u_periph.tmr_ctrl[0]) timer_started = 1;
            if (timer_started) begin
                if (top_timer_cnt != last_cnt) saw_timer_advance = 1;
                if (pwm_out) saw_pwm_high = 1;
                else saw_pwm_low = 1;
            end
            last_cnt = top_timer_cnt;
        end
    end

    task check;
        input condition;
        input [8*90-1:0] description;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                failures = failures + 1;
                $display("FAIL: %0s", description);
            end else $display("PASS: %0s", description);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        wait(halted === 1'b1);
        $display("CPU halted at PC=%h, t=%0t", pc_out, $time);
        repeat (80) @(posedge clk); // keep checking peripheral after CPU halt
        #1;
        check(saw_id, "CPU read peripheral ID = A8 at FF");
        check(saw_sample, "ADC started sampling channel 1");
        check(saw_eoc, "ADC completed SAR conversion");
        check(saw_rch, "CPU read ADC_RCH = 81 (valid, channel 1)");
        check(saw_data, "CPU read ADC_DATA = 56 (86 decimal)");
        check(saw_stat, "CPU read ADC_STAT = 10 (FIFO empty)");
        check(saw_irq, "ADC EOC asserted IRQ");
        check(saw_irq_cleared, "CPU cleared IRQ with W1C");
        check(timer_started, "CPU enabled timer");
        check(saw_timer_advance, "Timer counted after being enabled");
        check(saw_pwm_high && saw_pwm_low, "PWM produced HIGH and LOW levels");
        check(io_writes >= 9, "CPU issued peripheral write transactions");
        check(io_reads >= 4, "CPU issued peripheral read transactions");
        $display("RESULT: %0d checks, %0d failures", checks, failures);
        if (failures == 0) $display("*** P3 SOC TEST PASSED ***");
        else $display("*** P3 SOC TEST FAILED ***");
        $finish;
    end
    initial begin
        #10000;
        $display("*** P3 SOC TEST FAILED: TIMEOUT ***");
        $finish;
    end
endmodule
