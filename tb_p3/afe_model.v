`timescale 1ns / 1ps

module afe_model (
    input wire sample,
    input wire [1:0] ch,
    input wire [7:0] dac,
    output wire cmp
);
    reg [7:0] vhold;
    // Simulation-only initialization: avoid X before the first sample.
    initial vhold = 8'h00;

    // Giả lập lấy mẫu: Chốt điện áp ảo tùy thuộc vào kênh đang được chọn
    // Ideal quantized inputs: ch0=0x20, ch1=0x56, ch2=0x9B, ch3=0xE8.
    always @(negedge sample) begin
        case (ch)
            2'd0: vhold <= 8'h20; // Kênh 0
            2'd1: vhold <= 8'h56; // Kênh 1 (1.111 V)
            2'd2: vhold <= 8'h9B; // Kênh 2 (2.0 V)
            2'd3: vhold <= 8'hE8; // Kênh 3 (3.0 V)
        endcase
    end

    // Bộ so sánh Analog (DAC vs Điện áp chốt)
    assign cmp = (vhold >= dac);

endmodule