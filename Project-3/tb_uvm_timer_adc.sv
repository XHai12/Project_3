
`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================
// P3 - UVM TESTBENCH: TIMER + SAR ADC 8-BIT
// Direct peripheral verification
// ============================================================

// 1. BUS INTERFACE
interface p3_bus_if(input logic clk);
    logic rst_n = 0;
    logic cs = 0;
    logic we = 0;
    logic [3:0] addr = 0;
    logic [7:0] wdata = 0;

    wire [7:0] rdata;
    wire irq, pwm_out;
    wire adc_sample, adc_cmp;
    wire [1:0] adc_ch;
    wire [7:0] adc_dac, timer_cnt;
    wire adc_busy, adc_eoc;
    wire [7:0] adc_result;
endinterface


// ============================================================
// 2. TRANSACTION
// ============================================================
class p3_item extends uvm_sequence_item;

    bit we;
    bit [3:0] addr;
    bit [7:0] data;
    int unsigned idle_cycles;

    `uvm_object_utils(p3_item)

    function new(string name = "p3_item");
        super.new(name);
    endfunction
endclass


// ============================================================
// 3. SEQUENCE
// ============================================================
class p3_sequence extends uvm_sequence #(p3_item);

    `uvm_object_utils(p3_sequence)

    function new(string name = "p3_sequence");
        super.new(name);
    endfunction

    task bus_op(
        bit wr,
        bit [3:0] a,
        bit [7:0] d
    );
        p3_item tr;

        tr = p3_item::type_id::create("tr");
        start_item(tr);

        tr.we = wr;
        tr.addr = a;
        tr.data = d;
        tr.idle_cycles = 0;

        finish_item(tr);
    endtask

    task wr(bit [3:0] a, bit [7:0] d);
        bus_op(1, a, d);
    endtask

    task rd(bit [3:0] a);
        bus_op(0, a, 0);
    endtask

    task delay_cycles(int unsigned n);
        p3_item tr;

        tr = p3_item::type_id::create("idle_tr");

        start_item(tr);
        tr.idle_cycles = n;
        finish_item(tr);
    endtask

    task body();

        // PART A: PERIPHERAL ID
        rd(4'hF);

        // PART B: ADC SOFTWARE TRIGGER
        // Channel 1: 1.111V -> 0x56

        wr(4'h6, 8'h03);  // ADC_SMP = 3
        wr(4'h7, 8'h00);  // ADC_DIV = 0
        wr(4'hD, 8'h04);  // IRQ_EN ADC_EOC
        wr(4'h5, 8'h13);  // ADC EN + START + CH1

        delay_cycles(35);

        rd(4'hB);         // ADC_RCH = 0x81
        rd(4'hA);         // ADC_DATA = 0x56
        rd(4'hC);         // ADC_STAT = 0x10
        rd(4'hE);         // IRQ_STAT

        // Clear ADC EOC interrupt
        wr(4'hE, 8'h04);

        delay_cycles(4);

        // PART C: TIMER + PWM
        // PRESC = 0, LOAD = 9, CMP = 3

        wr(4'h1, 8'h00);
        wr(4'h2, 8'h09);
        wr(4'h3, 8'h03);
        wr(4'h0, 8'h01);

        delay_cycles(80);

        // PART D: TIMER TRIGGER ADC
        // Channel 2: 2.0V -> 0x9B

        wr(4'h2, 8'h27);  // LOAD = 39
        wr(4'h3, 8'h0C);  // CMP = 12
        wr(4'h5, 8'h25);  // Timer overflow trigger, CH2

        delay_cycles(150);

        rd(4'hB);         // ADC_RCH = 0x82
        rd(4'hA);         // ADC_DATA = 0x9B

    endtask
endclass


// ============================================================
// 4. DRIVER
// ============================================================
class p3_driver extends uvm_driver #(p3_item);

    `uvm_component_utils(p3_driver)

    virtual p3_bus_if vif;

    function new(
        string name,
        uvm_component parent
    );
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual p3_bus_if)::get(
            this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Driver cannot find interface")
    endfunction

    task run_phase(uvm_phase phase);
        p3_item tr;

        forever begin
            seq_item_port.get_next_item(tr);

            @(negedge vif.clk);

            vif.cs = 0;
            vif.we = 0;

            if (tr.idle_cycles != 0) begin

                repeat (tr.idle_cycles)
                    @(posedge vif.clk);

                @(negedge vif.clk);

            end else begin

                vif.addr = tr.addr;
                vif.wdata = tr.data;
                vif.we = tr.we;
                vif.cs = 1;

                @(negedge vif.clk);

                vif.cs = 0;
                vif.we = 0;
            end

            seq_item_port.item_done();
        end
    endtask
endclass


// ============================================================
// 5. MONITOR TRANSACTION
// ============================================================
class p3_sample extends uvm_sequence_item;

    bit cs, we;
    bit [3:0] addr;
    bit [7:0] wdata, rdata;

    bit irq, pwm_out;
    bit adc_sample, adc_eoc, adc_busy;

    bit [1:0] adc_ch;
    bit [7:0] adc_dac;
    bit [7:0] adc_result;
    bit [7:0] timer_cnt;

    `uvm_object_utils(p3_sample)

    function new(string name = "p3_sample");
        super.new(name);
    endfunction
endclass


// ============================================================
// 6. MONITOR
// ============================================================
class p3_monitor extends uvm_component;

    `uvm_component_utils(p3_monitor)

    virtual p3_bus_if vif;
    uvm_analysis_port #(p3_sample) ap;

    function new(
        string name,
        uvm_component parent
    );
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ap = new("ap", this);

        if (!uvm_config_db#(virtual p3_bus_if)::get(
            this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Monitor cannot find interface")
    endfunction

    task run_phase(uvm_phase phase);
        p3_sample s;

        forever begin
            @(posedge vif.clk);

            if (vif.rst_n) begin
                s = p3_sample::type_id::create("s");

                s.cs = vif.cs;
                s.we = vif.we;
                s.addr = vif.addr;
                s.wdata = vif.wdata;
                s.rdata = vif.rdata;

                s.irq = vif.irq;
                s.pwm_out = vif.pwm_out;

                s.adc_sample = vif.adc_sample;
                s.adc_ch = vif.adc_ch;
                s.adc_dac = vif.adc_dac;

                s.adc_eoc = vif.adc_eoc;
                s.adc_busy = vif.adc_busy;
                s.adc_result = vif.adc_result;

                s.timer_cnt = vif.timer_cnt;

                ap.write(s);
            end
        end
    endtask
endclass


// ============================================================
// 7. SCOREBOARD
// ============================================================
class p3_scoreboard extends uvm_component;

    `uvm_component_utils(p3_scoreboard)

    uvm_analysis_imp #(p3_sample, p3_scoreboard)
        analysis_export;

    int unsigned reads = 0;
    int unsigned writes = 0;

    int unsigned count_changes = 0;
    int unsigned pwm_high = 0;
    int unsigned pwm_low = 0;

    int unsigned conversions = 0;
    int unsigned adc_samples = 0;

    int unsigned checks = 0;
    int unsigned failures = 0;

    bit timer_enabled = 0;
    bit previous_valid = 0;
    bit irq_seen = 0;

    bit [7:0] previous_count = 0;

    bit id_ok = 0;
    bit rch1_ok = 0;
    bit data1_ok = 0;
    bit stat_ok = 0;

    bit irq_stat_ok = 0;
    bit irq_cleared = 0;

    bit rch2_ok = 0;
    bit data2_ok = 0;
    bit timer_cfg_ok = 0;

    function new(
        string name,
        uvm_component parent
    );
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        analysis_export = new("analysis_export", this);
    endfunction

    function void write(p3_sample s);

        if (s.adc_sample)
            adc_samples++;

        if (s.adc_eoc)
            conversions++;

        if (s.irq)
            irq_seen = 1;

        if (irq_seen && !s.irq)
            irq_cleared = 1;

        if (s.cs) begin

            if (s.we) begin

                writes++;

                if (s.addr == 4'h0 && s.wdata[0]) begin
                    timer_enabled = 1;
                    timer_cfg_ok = 1;
                end

            end else begin

                reads++;

                case (s.addr)

                    4'hF:
                        if (s.rdata == 8'hA8)
                            id_ok = 1;

                    4'hB: begin
                        if (s.rdata == 8'h81)
                            rch1_ok = 1;

                        if (s.rdata == 8'h82)
                            rch2_ok = 1;
                    end

                    4'hA: begin
                        if (s.rdata == 8'h56)
                            data1_ok = 1;

                        if (s.rdata == 8'h9B)
                            data2_ok = 1;
                    end

                    4'hC:
                        if (s.rdata == 8'h10)
                            stat_ok = 1;

                    4'hE:
                        if (s.rdata[2])
                            irq_stat_ok = 1;

                endcase
            end
        end

        if (timer_enabled) begin

            if (previous_valid &&
                s.timer_cnt != previous_count)
                count_changes++;

            if (s.pwm_out)
                pwm_high++;
            else
                pwm_low++;
        end

        previous_count = s.timer_cnt;
        previous_valid = 1;
    endfunction


    // FIXED: Renamed from check() to avoid UVM conflict
    function void verify_condition(
        bit ok,
        string msg
    );

        checks++;

        if (!ok) begin
            failures++;
            `uvm_error("P3_FAIL", msg)
        end else begin
            `uvm_info("P3_PASS", msg, UVM_LOW)
        end

    endfunction


    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        verify_condition(
            id_ok,
            "Peripheral ID read = A8"
        );

        verify_condition(
            adc_samples > 0,
            "SAR ADC asserted sample"
        );

        verify_condition(
            conversions >= 2,
            "ADC completed two conversions"
        );

        verify_condition(
            rch1_ok,
            "ADC_RCH returned 81 (channel 1)"
        );

        verify_condition(
            data1_ok,
            "ADC_DATA returned 56 (channel 1)"
        );

        verify_condition(
            stat_ok,
            "ADC_STAT returned 10 after FIFO pop"
        );

        verify_condition(
            irq_seen,
            "ADC EOC raised IRQ"
        );

        verify_condition(
            irq_stat_ok,
            "IRQ_STAT reported ADC EOC"
        );

        verify_condition(
            irq_cleared,
            "IRQ cleared after W1C"
        );

        verify_condition(
            timer_cfg_ok,
            "Timer enable register written"
        );

        verify_condition(
            count_changes >= 20,
            "Timer counter advanced"
        );

        verify_condition(
            pwm_high >= 10 && pwm_low >= 10,
            "Timer generated PWM HIGH and LOW"
        );

        verify_condition(
            rch2_ok,
            "Timer ADC_RCH returned 82"
        );

        verify_condition(
            data2_ok,
            "Timer ADC_DATA returned 9B"
        );

        verify_condition(
            writes >= 10 && reads >= 6,
            "Peripheral read/write transactions"
        );

        `uvm_info(
            "P3_SUMMARY",
            $sformatf(
                "RESULT: %0d checks, %0d failures",
                checks, failures
            ),
            UVM_NONE
        )

        if (failures == 0)
            `uvm_info(
                "P3_SUMMARY",
                "*** UVM TIMER + ADC TEST PASSED ***",
                UVM_NONE
            )
        else
            `uvm_error(
                "P3_SUMMARY",
                "*** UVM TIMER + ADC TEST FAILED ***"
            )

    endfunction
endclass


// ============================================================
// 8. AGENT
// ============================================================
class p3_agent extends uvm_agent;

    `uvm_component_utils(p3_agent)

    uvm_sequencer #(p3_item) sequencer;
    p3_driver driver;
    p3_monitor monitor;

    function new(
        string name,
        uvm_component parent
    );
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        sequencer = uvm_sequencer#(p3_item)
            ::type_id::create("sequencer", this);

        driver = p3_driver::type_id::create(
            "driver", this);

        monitor = p3_monitor::type_id::create(
            "monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        driver.seq_item_port.connect(
            sequencer.seq_item_export);
    endfunction
endclass


// ============================================================
// 9. ENVIRONMENT
// ============================================================
class p3_env extends uvm_env;

    `uvm_component_utils(p3_env)

    p3_agent agent;
    p3_scoreboard scoreboard;

    function new(
        string name,
        uvm_component parent
    );
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent = p3_agent::type_id::create(
            "agent", this);

        scoreboard = p3_scoreboard::type_id::create(
            "scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        agent.monitor.ap.connect(
            scoreboard.analysis_export);
    endfunction
endclass


// ============================================================
// 10. UVM TEST
// ============================================================
class p3_test extends uvm_test;

    `uvm_component_utils(p3_test)

    virtual p3_bus_if vif;
    p3_env env;

    function new(
        string name,
        uvm_component parent
    );
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual p3_bus_if)::get(
            this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Test cannot find interface")

        uvm_config_db#(virtual p3_bus_if)::set(
            this, "env.agent.*", "vif", vif);

        env = p3_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        p3_sequence seq;

        phase.raise_objection(this);

        wait (vif.rst_n === 1'b1);

        seq = p3_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);

        repeat (5) @(posedge vif.clk);

        phase.drop_objection(this);
    endtask
endclass


// ============================================================
// 11. TOP MODULE
// ============================================================
module tb_uvm_timer_adc;

    logic clk = 0;

    always #5 clk = ~clk;

    p3_bus_if bus(clk);

    // Peripheral DUT
    timer_adc8_cpu_if dut (
        .clk(clk),
        .rst_n(bus.rst_n),

        .cs(bus.cs),
        .we(bus.we),
        .addr(bus.addr),
        .wdata(bus.wdata),
        .rdata(bus.rdata),

        .irq(bus.irq),
        .adc_sample(bus.adc_sample),
        .adc_ch(bus.adc_ch),
        .adc_dac(bus.adc_dac),
        .adc_cmp(bus.adc_cmp),

        .pwm_out(bus.pwm_out),
        .dbg_tmr_cnt(bus.timer_cnt)
    );

    // Analog front-end
    afe_model analog_model (
        .sample(bus.adc_sample),
        .ch(bus.adc_ch),
        .dac(bus.adc_dac),
        .cmp(bus.adc_cmp)
    );

    // ADC debug signals
    assign bus.adc_busy =
        dut.u_periph.adc_busy;

    assign bus.adc_eoc =
        dut.u_periph.adc_eoc;

    assign bus.adc_result =
        dut.u_periph.adc_result;

    // Reset
    initial begin
        repeat (5) @(negedge clk);
        bus.rst_n = 1;
    end

    // Start UVM test
    initial begin

        uvm_config_db#(virtual p3_bus_if)::set(
            null, "uvm_test_top", "vif", bus);

        run_test("p3_test");
    end

    // Watchdog
    initial begin
        #20000;
        $fatal(1, "UVM Timer + ADC watchdog timeout");
    end

endmodule
