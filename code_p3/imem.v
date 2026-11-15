
`timescale 1ns / 1ps

module imem (
    input  wire [7:0] addr,
    output reg [15:0] instr
);

always @(*) begin
    case (addr)

        // ==========================
        // PART A: Read Peripheral ID
        // ==========================
        8'h00: instr = 16'h8EFF; // LDI R7, 0xFF
        8'h01: instr = 16'hA5C0; // LD  R2, [R7]
        8'h02: instr = 16'h8C80; // LDI R6, 0x80
        8'h03: instr = 16'hB580; // ST  R2, [R6]

        // ==========================
        // PART B: ADC Configuration
        // ==========================
        8'h04: instr = 16'h8EF6; // LDI R7, ADC_SMP
        8'h05: instr = 16'h8203; // LDI R1, 3
        8'h06: instr = 16'hB3C0; // ST R1, [R7]

        8'h07: instr = 16'h8EF7; // LDI R7, ADC_DIV
        8'h08: instr = 16'h8200; // LDI R1, 0
        8'h09: instr = 16'hB3C0; // ST R1, [R7]

        // Enable ADC End of Conversion IRQ
        8'h0A: instr = 16'h8EFD; // LDI R7, IRQ_EN
        8'h0B: instr = 16'h8204; // LDI R1, 0x04
        8'h0C: instr = 16'hB3C0; // ST R1, [R7]

        // Start SAR ADC on channel 1
        8'h0D: instr = 16'h8EF5; // LDI R7, ADC_CTRL
        8'h0E: instr = 16'h8213; // LDI R1, 0x13
        8'h0F: instr = 16'hB3C0; // ST R1, [R7]

        // ==========================
        // PART C: Wait for ADC
        // Addresses 10 - 23: NOP
        // ==========================

        // ==========================
        // PART D: Read ADC Results
        // ==========================

        // Read ADC_RCH
        8'h24: instr = 16'h8EFB; // LDI R7, 0xFB
        8'h25: instr = 16'hA5C0; // LD R2, [R7]
        8'h26: instr = 16'h8C81; // LDI R6, 0x81
        8'h27: instr = 16'hB580; // ST R2, [R6]

        // Read ADC_DATA
        8'h28: instr = 16'h8EFA; // LDI R7, 0xFA
        8'h29: instr = 16'hA5C0; // LD R2, [R7]
        8'h2A: instr = 16'h8C82; // LDI R6, 0x82
        8'h2B: instr = 16'hB580; // ST R2, [R6]

        // Read ADC_STAT
        8'h2C: instr = 16'h8EFC; // LDI R7, 0xFC
        8'h2D: instr = 16'hA5C0; // LD R2, [R7]
        8'h2E: instr = 16'h8C83; // LDI R6, 0x83
        8'h2F: instr = 16'hB580; // ST R2, [R6]

        // Clear ADC IRQ
        8'h30: instr = 16'h8EFE; // LDI R7, IRQ_STAT
        8'h31: instr = 16'h8204; // LDI R1, 0x04
        8'h32: instr = 16'hB3C0; // ST R1, [R7]

        // ==========================
        // PART E: Timer Configuration
        // ==========================

        // Prescaler = 0
        8'h33: instr = 16'h8EF1;
        8'h34: instr = 16'h8200;
        8'h35: instr = 16'hB3C0;

        // Timer LOAD = 9
        8'h36: instr = 16'h8EF2;
        8'h37: instr = 16'h8209;
        8'h38: instr = 16'hB3C0;

        // Timer CMP = 3
        8'h39: instr = 16'h8EF3;
        8'h3A: instr = 16'h8203;
        8'h3B: instr = 16'hB3C0;

        // Enable Timer
        8'h3C: instr = 16'h8EF0;
        8'h3D: instr = 16'h8201;
        8'h3E: instr = 16'hB3C0;

        // Stop CPU
        8'h3F: instr = 16'hF000; // HLT

        default: instr = 16'h0000; // NOP

    endcase
end

endmodule
