/***************************************************************************
 * Copyright (C) 2025 Intelligent System Architecture (ISA) Lab. All rights reserved. 
 * 
 * This file is written solely for academic use in AI Accelerator Design course assignement 
 * In School of Electrical and Electronics Engineering, Konkuk University 
 *
 * Unauthorized distribution is strictly prohibited.
 ***************************************************************************/
 
`timescale 1ns/1ns
 

// Behavioral memory 
module mem_behavior # (
    parameter firmware = "",
    parameter bitline = 16, 
    parameter bitaddr = 8, 
    parameter binary = 1 ) (
    input                   clk,
    input                   en,
    input                   we,
    input  [bitaddr-1:0]    addr,
    input  [bitline-1:0]    din,
    output [bitline-1:0]    dout
);
    reg                 test; 
    reg [bitline-1:0]   dout_;
    reg [bitline-1:0]   memory [0:2**bitaddr - 1];
    assign #1 dout = dout_;

    initial begin
        if (binary)
            $readmemb(firmware, memory);   
        else
            $readmemh(firmware, memory);
        test <= 1;
    end
 
    wire [bitline-1:0] memory_debug;
    assign memory_debug = memory[addr];
    
    always @ (posedge clk) begin
        if (we && en)
            memory[addr] <= din;
        if (~we && en)
            dout_ <= memory[addr];
        if (we && en)     
            test <= (memory[addr] == din);
    end
endmodule


///////////////////////////////////////////////////
module se8 (
    input clk,                    // Clock input
    input rst,                    // Reset input
    input en_for_mac,            // Enable signal for MAC operation
    input req_out,               // Request output signal
    input [7:0] data_from_left,  // 8-bit input from left neighbor
    input [15:0] data_from_top,  // 16-bit input from top neighbor
    output reg [7:0] data_to_right,   // Output data to right neighbor
    output reg [15:0] data_to_bottom, // Output data to bottom neighbor
    output reg en_for_mac_shift,     // Enable signal for MAC shift
    output se8_busy                  // Indicates if MAC is busy
);
    wire[15:0] accum;                 // Accumulator output from MAC
    reg en_shift[0:2];               // Shift register for enable signal
    reg[7:0] B_next[0:2];            // Shift register for B operand
    reg[7:0] A_next[0:2];            // Shift register for A operand
    reg[15:0] mac_res;              // Result from MAC unit
    reg mem_req;                    // Internal memory request flag
    reg[2:0] req_cnt;
    // Instantiate MAC unit
    mac8 MAC_mul (.clk(clk), .rst(rst), .en(en_for_mac), .A(data_from_left), .B(data_from_top[7:0]), .busy(se8_busy), .M(accum));

    always @(posedge clk) begin
        if(rst) begin      // Reset all signals to zero
            mac_res <= 0;
            en_shift[0] <= 0;
            en_shift[1] <= 0;
            en_shift[2] <= 0;
            A_next[0] <= 0;
            A_next[1] <= 0;
            A_next[2] <= 0;
            B_next[0] <= 0;
            B_next[1] <= 0;
            B_next[2] <= 0;
            mem_req <= 0;
            req_cnt <= 0;
        end 
        else 
        begin
            if (req_out)
            begin
                mem_req <= 1'b1; // Set memory request flag if output requested
            end
            else if (req_cnt == 4)
                mem_req <= 0;
        end 
    end

    always @(posedge clk) begin
        if(en_for_mac) begin                   // Load input when enable signal is high
            A_next[0] <= data_from_left;       // Load A operand
            B_next[0] <= data_from_top[7:0];   // Load B operand (LSB)
        end
        mac_res <= accum;                      // Store MAC result
        
        // Enable signal shift register
        en_shift[0] <= en_for_mac;                       
        en_shift[1] <= en_shift[0];
        en_shift[2] <= en_shift[1];
        en_for_mac_shift <= en_shift[2];      // To shift enable signal for mac after 4 cycles
        
        // Data shift register for A
        A_next[1] <= A_next[0];
        A_next[2] <= A_next[1];
        data_to_right <= A_next[2];           //Tp shift input A for mac after 4 cycles

        // Output logic for data_to_bottom
        if (req_out)
        begin
            data_to_bottom <= mac_res; // Send MAC result
            req_cnt <= req_cnt + 1;
            end
        else if (!req_out && mem_req)begin
            data_to_bottom <= data_from_top; // Send upper mac result to lower row
            req_cnt <= req_cnt + 1; end
        else 
        begin
            data_to_bottom <= {{8{B_next[2][7]}}, B_next[2]}; // Sign-extend and send for mac 
            B_next[1] <= B_next[0];
            B_next[2] <= B_next[1];
        end
    end
endmodule

module sa8_4x4(
    input clk,                     // Clock input
    input rst,                     // Reset input
    input en,                      // Enable input
    input req_out,                // Request output signal
    input [31:0] A,               // 4x8-bit matrix A
    input [31:0] B,               // 4x8-bit matrix B
    output reg [63:0] C,          // 4x16-bit matrix C
    output reg busy               // Overall busy flag
);
    wire[7:0] transA[0:3][0:3];   // Intermediate values of A flowing to the right
    wire[15:0] transB[0:3][0:3];   // Intermediate values of B flowing to the bottom
    wire en_shift[0:3][0:3];      // Enable signal propagation through the array
    wire[63:0] C_out;             // Collected C matrix output
    wire[15:0] busy_re;           // Individual busy signals from each PE
    wire busy_wire;               // Aggregated busy signal

    // Instantiate first processing element (PE) SE00
    se8 se00(
        .clk(clk),
        .rst(rst),
        .en_for_mac(en),
        .req_out(req_out),
        .data_from_left(A[31:24]),
        .data_from_top({8'b0,B[31:24]}),
        .data_to_right(transA[0][0]),
        .data_to_bottom(transB[0][0]),
        .en_for_mac_shift(en_shift[0][0]),
        .se8_busy(busy_re[0])
    );

    // Instantiate first column of each row (except first row)
    
        se8 se10(
            .clk(clk),
            .rst(rst),
            .en_for_mac(en_shift[0][0]), 
            .req_out(req_out),
            .data_from_left(A[8*(3)-1:8*(2)]),  
            .data_from_top(transB[0][0]),
            .data_to_right(transA[1][0]),
            .data_to_bottom(transB[1][0]),
            .en_for_mac_shift(en_shift[1][0]),
            .se8_busy(busy_re[1]));
            
       se8 se20(
            .clk(clk),
            .rst(rst),
            .en_for_mac(en_shift[1][0]), 
            .req_out(req_out),
            .data_from_left(A[8*(2)-1:8*(1)]),  
            .data_from_top(transB[1][0]),
            .data_to_right(transA[2][0]),
            .data_to_bottom(transB[2][0]),
            .en_for_mac_shift(en_shift[2][0]),
            .se8_busy(busy_re[2]));
            
        se8 se30(
            .clk(clk),
            .rst(rst),
            .en_for_mac(en_shift[2][0]),
            .req_out(req_out),
            .data_from_left(A[8*(1)-1:8*(0)]),
            .data_from_top(transB[2][0]),
            .data_to_right(transA[3][0]),
            .data_to_bottom(C_out[15:0]),
            .en_for_mac_shift(en_shift[3][0]),
            .se8_busy(busy_re[3])
        );
    genvar j,k,t,s;
    generate
    // Instantiate first row (except SE00)
    for(j=1; j<4; j=j+1) begin
        se8 eachcol(
            .clk(clk),
            .rst(rst),
            .en_for_mac(en_shift[0][j-1]),
            .req_out(req_out),
            .data_from_left(transA[0][j-1]),
            .data_from_top({8'b0,B[8*(4-j)-1:8*(3-j)]}),
            .data_to_right(transA[0][j]),
            .data_to_bottom(transB[0][j]),
            .en_for_mac_shift(en_shift[0][j]),
            .se8_busy(busy_re[4*j])
        );
    end

    // Instantiate internal PEs (not on first row/col or last row)
    for(k=1; k<3; k=k+1) begin
        for(t=1; t<4; t=t+1) begin
            se8 otherele(
                .clk(clk),
                .rst(rst),
                .en_for_mac(en_shift[k][t-1]),
                .req_out(req_out),
                .data_from_left(transA[k][t-1]),
                .data_from_top(transB[k-1][t]),
                .data_to_right(transA[k][t]),
                .data_to_bottom(transB[k][t]),
                .en_for_mac_shift(en_shift[k][t]),
                .se8_busy(busy_re[k+4*t])
            );
        end
    end

    // Instantiate last row of PEs and assign outputs to C
    for(s=1; s<4; s=s+1) begin
        se8 lastrow(
            .clk(clk),
            .rst(rst),
            .en_for_mac(en_shift[3][s-1]),
            .req_out(req_out),
            .data_from_left(transA[3][s-1]),
            .data_from_top(transB[2][s]),
            .data_to_right(transA[3][s]),
            .data_to_bottom(C_out[16*(s+1)-1:16*s]),
            .en_for_mac_shift(en_shift[3][s]),
            .se8_busy(busy_re[3+4*s])
        );
    end
    endgenerate

    // Aggregate busy signals from all PEs
    assign busy_wire = |busy_re;

    always @(*) begin
        if(rst) begin
            C <= 0;
            busy <= 0;
        end else begin
            busy <= busy_wire; // System busy if any PE is busy
            C <= {C_out[15:0], C_out[31:16], C_out[47:32], C_out[63:48]}; // Arrange C_out by columns for each row
        end
    end
endmodule

module mac8(
    input  clk,                          // Clock signal
    input  rst,                          // Reset signal
    input  en,                           // Enable signal
    input  [7:0] A,                      // 8-bit input A
    input  [7:0] B,                      // 8-bit input B
    output reg   busy,                   // Busy flag
    output reg [15:0] M                  // 16-bit accumulated output
);
    parameter S0 = 3'b000;              // Idle state
    parameter S1 = 3'b001;              // Multiply A_lo * B_lo
    parameter S2 = 3'b010;              // Multiply A_lo * B_hi
    parameter S3 = 3'b011;              // Multiply A_hi * B_lo
    parameter S4 = 3'b100;              // Multiply A_hi * B_hi

    reg [2:0] state;                    // FSM state
    reg [3:0] A_hi, A_lo, B_hi, B_lo;   // Split into Upper/lower parts of A and B (4bits each)
    reg [3:0] mul_a, mul_b;             // Current multiplier inputs
    wire [7:0] P_uu, P_us, P_su, P_ss;  // Outputs from different multipliers
    wire [7:0] P;                       // Selected product output
    wire [15:0] shifted_P;              // Shifted product
    wire [15:0] sum;                    // Result of M + shifted_P

    // Instantiate all 4 multiplier types
    multiplier_uu mul_uu (.A(mul_a), .B(mul_b), .P(P_uu)); // Unsigned * Unsigned
    multiplier_us mul_us (.A(mul_a), .B(mul_b), .P(P_us)); // Unsigned * Signed
    multiplier_su mul_su (.A(mul_a), .B(mul_b), .P(P_su)); // Signed * Unsigned
    multiplier_ss mul_ss (.A(mul_a), .B(mul_b), .P(P_ss)); // Signed * Signed

    // Select the correct multiplier output based on current state
    assign P = (state == S1) ? P_uu :  //if state is S1, P is output from mul_uu
               (state == S2) ? P_us :  //if state is S2, P is output from mul_us
               (state == S3) ? P_su :  //if state is S3, P is output from mul_su
               (state == S4) ? P_ss :  //if state is S4, P is output from mul_ss
               8'b0;                   //if state is not in S1 to S4, P is assigned as 8'b0

    // Shift the product depending on its position in final result
    assign shifted_P = (state == S1) ? {8'b0, P} :                           // No shift for LSB product
                       (state == S2 || state == S3) ? {{4{P[7]}}, P, 4'b0} : // Shift left by 4 bits with sign-extension
                       (state == S4) ? {P, 8'b0} :                           // Shift left by 8 bits
                       16'b0;                                                // Shifted_P=16'b0 if state is not in S1 to S4

    // Add M and shifted product
    adder16 adder_sum (.A(M), .B(shifted_P), .S(sum));     // Sum of M and shifted P to show mac_out

    // FSM to control operation sequence
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S0;                // Reset to idle
            M <= 16'b0;                 // Clear accumulator
            busy <= 1'b0;               // Clear busy flag
            A_hi <= 4'b0; A_lo <= 4'b0; // Clear A
            B_hi <= 4'b0; B_lo <= 4'b0; // Clear B
            mul_a <= 4'b0; mul_b <= 4'b0; // Clear multiplier inputs
        end else begin
            case (state)
                S0: begin
                    if (en) begin
                        A_hi <= A[7:4]; A_lo <= A[3:0];         // Split A
                        B_hi <= B[7:4]; B_lo <= B[3:0];         // Split B
                        mul_a <= A[3:0]; mul_b <= B[3:0];       // Set up for A_lo * B_lo
                        state <= S1;                            // Move to next state
                        busy <= 1;                              // Set busy
                    end
                end
                S1: begin
                    M <= sum;                    // Accumulate result of A_lo * B_lo (M+A_lo*B_lo)
                    mul_a <= A_lo; mul_b <= B_hi;// Next: A_lo * B_hi
                    state <= S2;
                end
                S2: begin
                    M <= sum;                    // Accumulate result (M+A_lo*B_hi)
                    mul_a <= A_hi; mul_b <= B_lo;// Next: A_hi * B_lo
                    state <= S3;
                end
                S3: begin
                    M <= sum;                    // Accumulate result (M+A_hi*B_lo)
                    mul_a <= A_hi; mul_b <= B_hi;// Next: A_hi * B_hi
                    state <= S4;
                end
                S4: begin
                    M <= sum;                    // Final accumulation (M+A_hi*B_hi)
                    if (en) begin
                        A_hi <= A[7:4]; A_lo <= A[3:0];         // Split A again for next input
                        B_hi <= B[7:4]; B_lo <= B[3:0];         // Split B again
                        mul_a <= A[3:0]; mul_b <= B[3:0];       // Restart with A_lo * B_lo
                        state <= S1;                            // Loop again
                        busy <= 1;                              // Keep busy
                    end else begin
                        state <= S0;                            // Go idle
                        busy <= 0;                              // Clear busy
                    end
                end
                default: begin
                    state <= S0;                                // Default fallback to idle
                    busy <= 0;
                end
            endcase
        end
    end
endmodule


module multiplier_uu(input [3:0] A, input [3:0] B, output [7:0] P);
    wire [7:0] A_ext = {4'b0, A};                      // Zero-extend A to 8 bits
    wire [7:0] B_ext = {4'b0, B};                      // Zero-extend B to 8 bits
    wire [7:0] partial0 = B_ext[0] ? (A_ext << 0) : 8'b0; // Compute partial product for bit 0
    wire [7:0] partial1 = B_ext[1] ? (A_ext << 1) : 8'b0; // Compute partial product for bit 1
    wire [7:0] partial2 = B_ext[2] ? (A_ext << 2) : 8'b0; // Compute partial product for bit 2
    wire [7:0] partial3 = B_ext[3] ? (A_ext << 3) : 8'b0; // Compute partial product for bit 3
    wire [7:0] sum0, sum1;                                // Intermediate sums
    adder8 ad0 (.A(partial0), .B(partial1), .S(sum0), .Cout());  // Intermediate sum0[7:0]=partial0+partial1
    adder8 ad1 (.A(partial2), .B(partial3), .S(sum1), .Cout());  // Intermediate sum1[7:0]=partial2+partial3
    adder8 ad2 (.A(sum0), .B(sum1), .S(P), .Cout());        // Final product P[7:0]=sum0+sum1
endmodule

module multiplier_us(input [3:0] A, input signed [3:0] B, output [7:0] P);
    wire [7:0] A_ext = {4'b0, A};                          // Zero-extend A
    wire signed [7:0] B_ext = { {4{B[3]}}, B };            // Sign-extend B
    wire [7:0] partial0 = B_ext[0] ? (A_ext << 0) : 8'b0;  // Compute partial product for bit 0
    wire [7:0] partial1 = B_ext[1] ? (A_ext << 1) : 8'b0;  // Compute partial product for bit 1
    wire [7:0] partial2 = B_ext[2] ? (A_ext << 2) : 8'b0;  // Compute partial product for bit 2
    wire [7:0] partial3_pre = B_ext[3] ? (A_ext << 3) : 8'b0; //To check if signed input B is positive or negative number
    wire [7:0] partial3 = B_ext[3] ? (~partial3_pre + 1) : 8'b0; // Two's complement to deal with signed input
    wire [7:0] sum0, sum1;
    adder8 ad0 (.A(partial0), .B(partial1), .S(sum0), .Cout());  // Intermediate sum0[7:0]=partial0+partial1
    adder8 ad1 (.A(partial2), .B(partial3), .S(sum1), .Cout());  // Intermediate sum1[7:0]=partial2+partial3
    adder8 ad2 (.A(sum0), .B(sum1), .S(P), .Cout());        //Final product P[7:0]=sum0+sum1
endmodule

module multiplier_su(input [3:0] A, input signed [3:0] B, output [7:0] P);
    wire signed [7:0] A_ext = { {4{A[3]}}, A };             // Sign-extend A
    wire [7:0] B_ext = {4'b0, B};                           // Zero-extend B
    wire [7:0] partial0 = A_ext[0] ? (B_ext << 0) : 8'b0;   // Compute partial product for bit 0
    wire [7:0] partial1 = A_ext[1] ? (B_ext << 1) : 8'b0;   // Compute partial product for bit 1
    wire [7:0] partial2 = A_ext[2] ? (B_ext << 2) : 8'b0;   // Compute partial product for bit 2
    wire [7:0] partial3_pre = A_ext[3] ? (B_ext << 3) : 8'b0;  //To check if signed input A is positive or negative number
    wire [7:0] partial3 = A_ext[3] ? (~partial3_pre + 1) : 8'b0; //Two's complement to deal with signed input
    wire [7:0] sum0, sum1;
    adder8 ad0 (.A(partial0), .B(partial1), .S(sum0), .Cout());  // Intermediate sum0[7:0]=partial0+partial1
    adder8 ad1 (.A(partial2), .B(partial3), .S(sum1), .Cout());  // Intermediate sum1[7:0]=partial2+partial3
    adder8 ad2 (.A(sum0), .B(sum1), .S(P), .Cout());       //Final product P[7:0]=sum0+sum1
endmodule

module multiplier_ss(
    input signed [3:0] A, 
    input signed [3:0] B, 
    output [7:0] P
);
    wire signed [7:0] A_ext = { {4{A[3]}}, A };             // Sign-extend A
    wire [7:0] partial0 = B[0] ? (A_ext << 0) : 8'b0;       // Compute partial product for bit 0
    wire [7:0] partial1 = B[1] ? (A_ext << 1) : 8'b0;       // Compute partial product for bit 1
    wire [7:0] partial2 = B[2] ? (A_ext << 2) : 8'b0;       // Compute partial product for bit 2
    wire [7:0] partial3_pre = B[3] ? (A_ext << 3) : 8'b0;   //To check if signed input B is positive or negative number
    wire [7:0] partial3 = B[3] ? (~partial3_pre + 1'b1) : 8'b0; //Two's complement to deal with signed input
    wire [7:0] sum0, sum1;
    adder8 ad0 (.A(partial0), .B(partial1), .S(sum0), .Cout());  // Intermediate sum0[7:0]=partial0+partial1
    adder8 ad1 (.A(partial2), .B(partial3), .S(sum1), .Cout());  // Intermediate sum1[7:0]=partial2+partial3
    adder8 ad2 (.A(sum0), .B(sum1), .S(P), .Cout());       //Final product P[7:0]=sum0+sum1
endmodule

module adder8(
    input [7:0] A, 
    input [7:0] B,
    output [7:0] S, 
    output Cout
);
    wire c1, c2, c3, c4, c5, c6, c7;
    half_adder ha0 (.a(A[0]), .b(B[0]), .sum(S[0]), .carry(c1)); // First bit using half adder
    full_adder fa1 (.a(A[1]), .b(B[1]), .cin(c1), .sum(S[1]), .carry(c2)); //To make sum and carry for next bit using full adder
    full_adder fa2 (.a(A[2]), .b(B[2]), .cin(c2), .sum(S[2]), .carry(c3)); //To make sum and carry for next bit using full adder
    full_adder fa3 (.a(A[3]), .b(B[3]), .cin(c3), .sum(S[3]), .carry(c4)); //To make sum and carry for next bit using full adder
    full_adder fa4 (.a(A[4]), .b(B[4]), .cin(c4), .sum(S[4]), .carry(c5)); //To make sum and carry for next bit using full adder
    full_adder fa5 (.a(A[5]), .b(B[5]), .cin(c5), .sum(S[5]), .carry(c6)); //To make sum and carry for next bit using full adder
    full_adder fa6 (.a(A[6]), .b(B[6]), .cin(c6), .sum(S[6]), .carry(c7)); //To make sum and carry for next bit using full adder
    full_adder fa7 (.a(A[7]), .b(B[7]), .cin(c7), .sum(S[7]), .carry(Cout)); //To make sum and final carry bit using full adder
endmodule

module adder16(input [15:0] A, input [15:0] B, output [15:0] S);
    assign S = A + B; // Simple 16-bit addition
endmodule

module full_adder(
    input a, 
    input b, 
    input cin, 
    output sum, 
    output carry
);
    assign sum = a ^ b ^ cin; // To make sum for single bit by using xor with input a, b ,and prior bit's carry
    assign carry = (a & b) | (b & cin) | (a & cin); // To make carry for next bit
endmodule

module half_adder(
    input a, 
    input b, 
    output sum, 
    output carry
);
    assign sum = a ^ b; // To make sum for single bit by using xor with input a, b
    assign carry = a & b; // To make carry for next bit
endmodule



/* FOR YOUR CONVENIENCE, A MODULE NAMED ctrl IS DECLARED and top MODULE IS DEFINED TO WORK WITH IT */
/* YOU MAY COMPLETE ctrl SO THAT top FUNCTIONS CORRECTLY WITHOUT MODIFYING ITS DEFINITION */
/* ALTERNATIVELY, YOU CAN MODIFY OR EVEN REMOVE ctrl AND IMPLEMENT top IN YOUR OWN WAY, */
/* AS LONG AS YOU DO NOT CHANGE THE I/O CONFIGURTION OF top */

module ctrl (
    input               clk,          // System clock
    input               rst,          // System reset
    input               run,          // Start computation signal
    input               batch_mode,   // Mode select (0: 8x8, 1: 8x16)
    output reg [1:0]    state,        // Current FSM state
    
    // Memory A interface (weight matrix)
    output reg          re_A,         // Read enable for memory A
    output reg [6:0]    addr_A,       // Address for memory A
    input      [7:0]    data_A,       // Data from memory A
    
    // Memory B interface (input matrix)
    output reg          re_B,         // Read enable for memory B
    output reg [6:0]    addr_B,       // Address for memory B
    input      [7:0]    data_B,       // Data from memory B
    
    // Memory C interface (output matrix)
    output reg          we_C,         // Write enable for memory C
    output reg [6:0]    addr_C,       // Address for memory C
    output reg [15:0]   data_C,       // Data to memory C
    
    // Systolic Array interface
    output reg          sa_en,        // Enable signal for systolic array
    output reg          sa_req_out,   // Request output from systolic array
    input               sa_busy,      // Busy signal from systolic array
    output reg [31:0]   sa_data_A,    // A matrix data to systolic array
    output reg [31:0]   sa_data_B,    // B matrix data to systolic array
    input      [63:0]   sa_data_C     // C matrix data from systolic array
);
    // FSM state definitions
    parameter IDLE = 2'b00, LOAD = 2'b01, COMPUTE = 2'b10, WRITE = 2'b11;
    
    // Tile tracking variables
    reg [1:0] tile_row, tile_col, tile_mid; // Current tile position and inner dimension
    reg [3:0] load_count;            // Counter for loading 4x4 tile elements
    reg [5:0] compute_cycle;         // Counter for computation cycles
    reg [3:0] write_count;           // Counter for writing 4x4 tile elements
    reg [7:0] A_buffer [0:3][0:3];   // Local buffer for A tile data
    reg [7:0] B_buffer [0:3][0:3];   // Local buffer for B tile data
    reg [15:0] C_accum [0:3][0:3];   // Accumulator for C tile results
    reg [3:0] mult_done;             // Counter for completed multiplications
    reg load_delay;                  // Delay flag for memory read latency
    reg [2:0] data_cnt;              // Counter for processed tiles
    reg mem_req;                     // Memory request flag
    reg buffer_delay;                // Buffer delay for output timing
    reg [2:0] output_cnt;            // Counter for output collection
    reg [3:0] w_cnt;                 // Write counter for result storage
    integer i, j;                    // Loop variables for buffer initialization
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin // Reset all control signals and variables
            state <= IDLE;
            re_A <= 0;
            re_B <= 0;
            we_C <= 0;
            addr_A <= 0;
            addr_B <= 0;
            addr_C <= 0;
            data_C <= 0;
            sa_en <= 0;
            sa_req_out <= 0;
            sa_data_A <= 0;
            sa_data_B <= 0;
            tile_row <= 0;
            tile_col <= 0;
            tile_mid <= 0;
            load_count <= 0;
            compute_cycle <= 0;
            write_count <= 0;
            mult_done <= 0;
            load_delay <= 0;
            data_cnt <= 0;
            buffer_delay <= 0;
            mem_req <= 0;
            output_cnt <= 0;
            w_cnt <= 0;

            // Initialize A buffer to zero
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 4; j = j + 1)
                    A_buffer[i][j] <= 0; 
            // Initialize B buffer to zero
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 4; j = j + 1)
                    B_buffer[i][j] <= 0;
            // Initialize C accumulator to zero
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) 
                    C_accum[i][j] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin // Wait for run signal to start computation
                    if (run) begin
                        state <= LOAD;              // Transition to load state
                        re_A <= 1;                  // Enable memory A read
                        re_B <= 1;                  // Enable memory B read
                        addr_A <= 0;                // Start from address 0
                        addr_B <= 0;
                        load_count <= 0;            // Reset counters
                        write_count <= 0;
                        w_cnt <= 0;
                        tile_row <= 0;              // Start from tile [0][0]
                        tile_col <= 0;
                        tile_mid <= 0;              // Start inner dimension k=0
                        mult_done <= 0;
                        load_delay <= 1;            // Set delay for first memory read
                        mem_req <= 0;
                        output_cnt <= 0;
                        data_cnt <= 0;
                        buffer_delay <= 0;
                    end
                end
                
                // LOAD state: Load 4x4 tile data from memory into local buffers
                LOAD: begin
                    if (load_delay) begin
                        // Wait for memory read latency (1 cycle)
                        load_delay <= 0;
                    end else begin
                        // Store data from previous cycle (data_A, data_B are valid now)
                        if (load_count < 16) begin // Load 16 elements (4x4 tile)
                            A_buffer[load_count[3:2]][load_count[1:0]] <= data_A;
                            B_buffer[load_count[3:2]][load_count[1:0]] <= data_B;
                        end
                        if (load_count < 15) begin // Continue loading until all 16 elements
                           if (batch_mode == 0) begin // 8x8 mode addressing
                                load_count <= load_count + 1;
                                if (load_count == 3 || load_count == 7 || load_count == 11) begin
                                    addr_A <= addr_A + 5;  // Skip to next row (8-4+1=5)
                                    addr_B <= addr_B + 5;
                                end else begin  
                                    addr_A <= addr_A + 1;  // Sequential within row
                                    addr_B <= addr_B + 1;
                                end        
                                load_delay <= 1; // Set delay for next read
                           end else begin // 8x16 mode addressing
                                load_count <= load_count + 1;
                                if (load_count == 3 || load_count == 7 || load_count == 11) begin
                                    addr_A <= addr_A + 5;   // A matrix still 8x8
                                    addr_B <= addr_B + 13;  // B matrix is 8x16 (16-4+1=13)
                                end else begin  
                                    addr_A <= addr_A + 1;
                                    addr_B <= addr_B + 1;
                                end        
                                load_delay <= 1; // Set delay for next read
                           end    
                        end else if(load_count == 15) begin
                            // All 16 elements loaded, transition to compute
                            re_A <= 0;                 // Disable memory reads
                            re_B <= 0;
                            state <= COMPUTE;           // Move to compute state
                            load_count <= 0;            // Reset counter
                            compute_cycle <= 0;         // Reset compute counter
                            sa_en <= 0;                 // Initialize systolic array enable
                        end
                    end
                end
                
                COMPUTE: begin // Systolic array computation with diagonal data injection
                    if (compute_cycle < 25) begin // 25 cycles for complete computation
                        // Activate sa_en at cycles 0, 4, 8, 12 (diagonal injection timing)
                        if (compute_cycle == 0 || compute_cycle == 4 || compute_cycle == 8 || compute_cycle == 12) begin
                            sa_en <= 1;             // Enable systolic array
                        end else begin
                            sa_en <= 0;             // Disable between injections
                        end
                        
                        // Diagonal data injection pattern for systolic array
                        if (compute_cycle == 0) // First diagonal: single element
                            {sa_data_A, sa_data_B} <= {{A_buffer[0][0], 8'b0, 8'b0, 8'b0}, {B_buffer[0][0], 8'b0, 8'b0, 8'b0}};
                        else if (compute_cycle == 4) // Second diagonal: 2 elements
                            {sa_data_A, sa_data_B} <= {{A_buffer[0][1], A_buffer[1][0], 8'b0, 8'b0}, {B_buffer[1][0], B_buffer[0][1], 8'b0, 8'b0}};
                        else if (compute_cycle == 8) // Third diagonal: 3 elements
                            {sa_data_A, sa_data_B} <= {{A_buffer[0][2], A_buffer[1][1], A_buffer[2][0], 8'b0}, {B_buffer[2][0], B_buffer[1][1], B_buffer[0][2], 8'b0}};
                        else if (compute_cycle == 12) // Fourth diagonal: 4 elements (full)
                            {sa_data_A, sa_data_B} <= {{A_buffer[0][3], A_buffer[1][2], A_buffer[2][1], A_buffer[3][0]}, {B_buffer[3][0], B_buffer[2][1], B_buffer[1][2], B_buffer[0][3]}};
                        else if (compute_cycle == 16) // Fifth diagonal: 3 elements
                            {sa_data_A, sa_data_B} <= {{8'b0, A_buffer[1][3], A_buffer[2][2], A_buffer[3][1]}, {8'b0, B_buffer[3][1], B_buffer[2][2], B_buffer[1][3]}};
                        else if (compute_cycle == 20) // Sixth diagonal: 2 elements
                            {sa_data_A, sa_data_B} <= {{8'b0, 8'b0, A_buffer[2][3], A_buffer[3][2]}, {8'b0, 8'b0, B_buffer[3][2], B_buffer[2][3]}};
                        else if (compute_cycle == 24) // Seventh diagonal: 1 element
                            {sa_data_A, sa_data_B} <= {{8'b0, 8'b0, 8'b0, A_buffer[3][3]}, {8'b0, 8'b0, 8'b0, B_buffer[3][3]}};
                         compute_cycle <= compute_cycle + 1; // Increment cycle counter
                    end else if(compute_cycle == 25) begin // Computation complete
                       // Check if this is second multiplication (mult_done == 1)
                       if (mult_done == 1 && !sa_busy) begin 
                           if (!sa_busy && !mem_req) begin
                              sa_req_out <= 1;         // Request results from systolic array
                              mem_req <= 1;            // Set memory request flag
                           end else if (sa_req_out) begin 
                              sa_req_out <= 0;         // Clear request
                              buffer_delay <= 1;       // Set buffer delay
                           end
                      
                           // Collect results from systolic array (4 cycles)
                           if (mem_req && buffer_delay && output_cnt < 4) begin
                              C_accum[3-output_cnt][0] <= sa_data_C[63:48]; // Column-wise result storage
                              C_accum[3-output_cnt][1] <= sa_data_C[47:32];
                              C_accum[3-output_cnt][2] <= sa_data_C[31:16];
                              C_accum[3-output_cnt][3] <= sa_data_C[15:0];
                              output_cnt <= output_cnt + 1; // Increment output counter
                           end  
                           if (output_cnt == 4) begin // All results collected
                               buffer_delay <= 0;
                               state <= WRITE;          // Transition to write state
                               write_count <= 0;
                               we_C <= 1;               // Enable memory C write
                               data_C <= C_accum[0][0]; // Start with first element
                               w_cnt <= 1; 
                               mult_done <= 0;          // Reset multiplication counter
                               output_cnt <= 0;
                               mem_req <= 0;
                           end
                       // First multiplication complete (mult_done == 0)                           
                       end else if(mult_done == 0) begin                          
                           tile_mid <= 1;               // Move to next inner dimension
                           state <= LOAD;               // Load next tile pair
                           re_A <= 1;
                           re_B <= 1;
                           if (batch_mode == 0) begin   // 8x8 mode addressing
                               addr_A <= (tile_row * 32) + ((tile_mid + 1) * 4); // A[tile_row][tile_mid+1]
                               addr_B <= ((tile_mid + 1) * 32) + (tile_col * 4); // B[tile_mid+1][tile_col]
                           end else begin               // 8x16 mode addressing
                               addr_A <= (tile_row * 32) + ((tile_mid + 1) * 4); 
                               addr_B <= ((tile_mid + 1) * 64) + (tile_col * 4); // B matrix is wider
                           end
                           load_delay <= 1;
                           mult_done <= mult_done + 1;  // Increment multiplication counter
                       end
                    end
                end
                
                WRITE: begin // Write accumulated results to memory C             
                       if (w_cnt < 16) begin            // Prepare next data element
                           data_C <= C_accum[w_cnt[3:2]][w_cnt[1:0]]; 
                           w_cnt <= w_cnt + 1;            
                       end                         
                       if (write_count < 15) begin      // Write 16 elements total
                          if (batch_mode == 0) begin   // 8x8 mode addressing
                              write_count <= write_count + 1;                         
                              if (write_count == 3 || write_count == 7 || write_count == 11) begin
                                  addr_C <= addr_C + 5; // Skip to next row
                              end else begin
                                  addr_C <= addr_C + 1; // Sequential within row                  
                              end 
                          end else begin               // 8x16 mode addressing
                              write_count <= write_count + 1;                         
                              if (write_count == 3 || write_count == 7 || write_count == 11) begin
                                  addr_C <= addr_C + 13; // Wider result matrix
                              end else begin
                                  addr_C <= addr_C + 1;                   
                              end                                               
                          end
                       end
                       if(write_count == 15) begin     // All elements written
                            w_cnt <= 0;   
                            we_C <= 0;                 // Disable write
                            write_count <= 0;
                            mult_done <= 0;
                            data_cnt <= data_cnt + 1;  // Increment tile counter
                            if (batch_mode == 0) begin
                                 // 8x8 mode: 4 tiles total (2x2 grid)
                                 if (data_cnt == 3) begin
                                     state <= IDLE;     // All tiles complete
                                     addr_C <= 0;       // Reset address
                                     data_cnt <= 0;     // Reset counter
                                 end else if(data_cnt == 0) begin // Tile [0][1]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;     // Reset inner dimension
                                     tile_col <= tile_col + 1; // Next column
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 0;       // A[0][0]
                                     addr_B <= 4;       // B[0][1]
                                     addr_C <= 4;       // C[0][1]
                                 end else if(data_cnt == 1) begin // Tile [1][0]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;                                
                                     tile_col <= 0;     // Reset column
                                     tile_row <= tile_row + 1; // Next row
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 32;      // A[1][0]
                                     addr_B <= 0;       // B[0][0]
                                     addr_C <= 32;      // C[1][0]
                                 end else if(data_cnt == 2) begin // Tile [1][1]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;
                                     tile_row <= 1;
                                     tile_col <= tile_col + 1;
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 32;      // A[1][0]
                                     addr_B <= 4;       // B[0][1]
                                     addr_C <= 36;      // C[1][1]
                                 end      
                            end else begin
                                 // 8x16 mode: 8 tiles total (2x4 grid)
                                 if (data_cnt == 7) begin
                                     state <= IDLE;     // All tiles complete
                                     addr_C <= 0;
                                     data_cnt <= 0;
                                 end else if(data_cnt == 0) begin // Tile [0][1]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;
                                     tile_col <= tile_col + 1;
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 0;
                                     addr_B <= 4;
                                     addr_C <= 4;
                                 end else if(data_cnt == 1) begin // Tile [1][0]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;                                
                                     tile_col <= 0;
                                     tile_row <= tile_row + 1;
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 32;
                                     addr_B <= 0;
                                     addr_C <= 64;      // Different C addressing for 8x16
                                 end else if(data_cnt == 2) begin // Tile [1][1]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;
                                     tile_row <= 1;
                                     tile_col <= tile_col + 1;
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 32;
                                     addr_B <= 4;
                                     addr_C <= 68;
                                  end else if(data_cnt == 3) begin // Tile [0][2]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;
                                     tile_row <= 0;
                                     tile_col <= 2;
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 0;
                                     addr_B <= 8;
                                     addr_C <= 8;    
                                  end else if(data_cnt == 4) begin // Tile [0][3]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;
                                     tile_row <= 0;
                                     tile_col <= 3;
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 0;
                                     addr_B <= 12;
                                     addr_C <= 12;
                                  end else if(data_cnt == 5) begin // Tile [1][2]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;
                                     tile_row <= 1;
                                     tile_col <= 2;
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 32;
                                     addr_B <= 8;
                                     addr_C <= 72;
                                  end else if(data_cnt == 6) begin // Tile [1][3]
                                     state <= LOAD;
                                     load_delay <= 1;
                                     tile_mid <= 0;
                                     tile_row <= 1;
                                     tile_col <= 3;
                                     re_A <= 1;
                                     re_B <= 1;
                                     addr_A <= 32;
                                     addr_B <= 12;
                                     addr_C <= 76;
                                  end                                                                                                                                      
                            end
                       end
                end
            endcase
        end
    end
endmodule

// ========================================
// Top Module - Integrates Controller and Systolic Array
// ========================================
module top (
    input               clk,         // System clock
    input               rst,         // System reset
    input               run,         // Start computation signal
    input               batch_mode,  // Mode select (0: 8x8, 1: 8x16)
    output  reg [1:0]   state,       // Current state (from controller)
    output  reg         re_A,        // Read enable for memory A
    output  reg [6:0]   addr_A,      // Address for memory A
    input       [7:0]   data_A,      // Data from memory A
    
    output  reg         re_B,        // Read enable for memory B
    output  reg [6:0]   addr_B,      // Address for memory B
    input       [7:0]   data_B,      // Data from memory B
    
    output  reg         we_C,        // Write enable for memory C
    output  reg [6:0]   addr_C,      // Address for memory C
    output  reg [15:0]  data_C       // Data to memory C
);

    // Internal signals from Controller
    wire    [1:0]   state_;          // State from controller
    wire            re_A_, re_B_, we_C_; // Memory control signals from controller
    wire    [6:0]   addr_A_, addr_B_, addr_C_; // Addresses from controller
    wire    [15:0]  data_C_;         // Data from controller
    reg             we_C_delay;      // Delayed write enable for reset generation
    
    // Systolic Array interface signals
    wire         sa_en, sa_req_out, sa_busy; // Control signals for systolic array
    wire   [31:0]   sa_data_A, sa_data_B;    // Data inputs to systolic array
    wire   [63:0]   sa_data_C;               // Data output from systolic array
    wire            sa_local_rst;            // Local reset for systolic array
    
    // Connect controller outputs to top module outputs
    always @ (*) begin
        state = state_;              // Pass through state
        re_A = re_A_; re_B = re_B_; we_C = we_C_; // Pass through memory controls
        addr_A = addr_A_; addr_B = addr_B_; addr_C = addr_C_; // Pass through addresses
        data_C = data_C_;            // Pass through data
    end
    
    // Generate delayed write enable signal
    always @ (posedge clk) begin
        if (rst)    we_C_delay <= 0;
        else        we_C_delay <= we_C_; 
    end
    
    // Generate local reset for systolic array on write enable edge
    assign sa_local_rst = we_C_ && ~we_C_delay;        
    
    // Instantiate Controller
    ctrl        U_ctrl  (   .clk(clk), .rst(rst), .run(run), .batch_mode(batch_mode), .state(state_), 
                            .re_A(re_A_), .addr_A(addr_A_), .data_A(data_A), 
                            .re_B(re_B_), .addr_B(addr_B_), .data_B(data_B),
                            .we_C(we_C_), .addr_C(addr_C_), .data_C(data_C_),
                            .sa_en(sa_en), .sa_req_out(sa_req_out), .sa_busy(sa_busy),
                            .sa_data_A(sa_data_A), .sa_data_B(sa_data_B), .sa_data_C(sa_data_C)   );
    
    // Instantiate 4x4 Systolic Array
    sa8_4x4     U_sa    (   .clk(clk), .rst(rst || sa_local_rst), .en(sa_en), .req_out(sa_req_out), .busy(sa_busy),
                            .A(sa_data_A), .B(sa_data_B), .C(sa_data_C)  );
    
endmodule

// ========================================
// Normalization Module
// ========================================
module norm (
    input               clk,         // Clock signal
    input               rst,         // Reset signal
    input               en,          // Enable signal
    input       [15:0]  din,         // 16-bit input data
    output reg  [7:0]   dout,        // 8-bit normalized output
    output reg          valid        // Valid output signal
);
    always @(posedge clk) begin
        if (rst) begin
            dout <= 8'd0;            // Clear output on reset
            valid <= 1'b0;          // Clear valid flag
        end else if (en) begin
            dout <= din[12:5];       // Shift 5bit to right by extracting middle 8 bits for normalization 
            valid <= 1'b1;          // Set valid flag
        end else begin
            valid <= 1'b0;          // Clear valid when not enabled
        end
    end
endmodule

module relu (
    input               clk,         // Clock signal
    input               rst,         // Reset signal
    input               en,          // Enable signal
    input       [7:0]   din,         // 8-bit input data
    output reg  [7:0]   dout,        // 8-bit output data
    output reg          valid        // Valid output signal
);
    always @(posedge clk) begin
        if (rst) begin
            dout <= 8'd0;            // Clear output on reset
            valid <= 1'b0;          // Clear valid flag
        end else if (en) begin
            // ReLU function: if MSB is 1 dout <= 0, else dout <= din
            dout <= din[7] ? 8'd0 : din;
            valid <= 1'b1;          // Set valid flag
        end else begin
            valid <= 1'b0;          // Clear valid when not enabled
        end
    end
endmodule

///////////////////////////////////////////////////