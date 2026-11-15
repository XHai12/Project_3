`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// =====================================================================
// 1. GIAO DIỆN (INTERFACE) BUS TÍN HIỆU
// =====================================================================
interface apb_if (input logic clk, input logic rst_n);
    logic cs;
    logic we;
    logic [3:0] addr;
    logic [7:0] wdata;
    logic [7:0] rdata;
endinterface

// =====================================================================
// 2. TRANSACTION (GÓI DỮ LIỆU)
// =====================================================================
class apb_item extends uvm_sequence_item;
    rand bit we;
    rand bit [3:0] addr;
    rand bit [7:0] wdata;
    bit [7:0] rdata;

    `uvm_object_utils(apb_item)
    function new(string name = "apb_item"); 
        super.new(name); 
    endfunction
endclass

// =====================================================================
// 3. SEQUENCE (KỊCH BẢN TEST TIMER)
// Cấu hình Prescaler, Load, Compare và Bật Timer
// =====================================================================
class timer_seq extends uvm_sequence #(apb_item);
    `uvm_object_utils(timer_seq)
    function new(string name = "timer_seq"); super.new(name); endfunction

    task body();
        apb_item req;
        `uvm_info("SEQ", "Bat dau cau hinh Timer...", UVM_LOW)

        // B1: Ghi TMR_PRESC (0x1) = 3
        req = apb_item::type_id::create("req");
        start_item(req); req.we = 1; req.addr = 4'h1; req.wdata = 8'h03; finish_item(req);

        // B2: Ghi TMR_LOAD (0x2) = 9
        req = apb_item::type_id::create("req");
        start_item(req); req.we = 1; req.addr = 4'h2; req.wdata = 8'h09; finish_item(req);

        // B3: Ghi TMR_CMP (0x3) = 4
        req = apb_item::type_id::create("req");
        start_item(req); req.we = 1; req.addr = 4'h3; req.wdata = 8'h04; finish_item(req);

        // B4: Ghi TMR_CTRL (0x0) = 1 (Enable Timer)
        req = apb_item::type_id::create("req");
        start_item(req); req.we = 1; req.addr = 4'h0; req.wdata = 8'h01; finish_item(req);

        // Đợi 200ns cho Timer đếm
        #200;

        // B5: Đọc giá trị đếm hiện tại TMR_CNT (0x4)
        `uvm_info("SEQ", "Doc gia tri bo dem Timer...", UVM_LOW)
        req = apb_item::type_id::create("req");
        start_item(req); req.we = 0; req.addr = 4'h4; finish_item(req);
    endtask
endclass

// =====================================================================
// 4. DRIVER (BƠM TÍN HIỆU VÀO MẠCH)
// =====================================================================
class apb_driver extends uvm_driver #(apb_item);
    `uvm_component_utils(apb_driver)
    virtual apb_if vif;

    function new(string name, uvm_component parent); 
        super.new(name, parent); 
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Khong tim thay Virtual Interface!")
    endfunction

    task run_phase(uvm_phase phase);
        vif.cs <= 0; vif.we <= 0;
        forever begin
            seq_item_port.get_next_item(req);
            @(posedge vif.clk);
            vif.cs <= 1;
            vif.we <= req.we;
            vif.addr <= req.addr;
            if(req.we) vif.wdata <= req.wdata;
            @(posedge vif.clk);
            vif.cs <= 0;
            seq_item_port.item_done();
        end
    endtask
endclass

// =====================================================================
// 5. AGENT & ENVIRONMENT
// =====================================================================
class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)
    apb_driver driver;
    uvm_sequencer #(apb_item) sequencer;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver = apb_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(apb_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

class timer_env extends uvm_env;
    `uvm_component_utils(timer_env)
    apb_agent agent;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = apb_agent::type_id::create("agent", this);
    endfunction
endclass

// =====================================================================
// 6. UVM TEST
// =====================================================================
class timer_test extends uvm_test;
    `uvm_component_utils(timer_test)
    timer_env env;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = timer_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        timer_seq seq;
        phase.raise_objection(this);
        seq = timer_seq::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #50;
        phase.drop_objection(this);
    endtask
endclass

// =====================================================================
// 7. TOP MODULE (MÔI TRƯỜNG CHẠY)
// =====================================================================
module tb_uvm_timer();
    logic clk;
    logic rst_n;

    // Khởi tạo xung Clock
    initial begin clk = 0; forever #5 clk = ~clk; end

    // Kết nối Interface
    apb_if vif(clk, rst_n);

    // GỌI KHỐI MẠCH NGOẠI VI (DUY NHẤT KHỐI TIMER + ADC ĐỂ TEST)
    timer_adc8_top u_dut (
        .clk(clk), .rst_n(rst_n), 
        .cs(vif.cs), .we(vif.we), 
        .addr(vif.addr), .wdata(vif.wdata), .rdata(vif.rdata),
        .irq(), .adc_sample(), .adc_ch(), .adc_dac(), .adc_cmp(1'b0), .pwm_out()
    );

    initial begin
        // Gán interface vào UVM database
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", vif);
        
        // Reset hệ thống
        rst_n = 0; #20; rst_n = 1;

        // Chạy Test UVM
        run_test("timer_test");
    end
endmodule