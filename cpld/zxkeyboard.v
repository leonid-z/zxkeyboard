//-------------------------------------------------------------
// ZX keyboard operated by PS/2 keyboard
// extra functionality: reset, magic key, turbo mode
//
//-------------------------------------------------------------
//              D0       D1       D2       D3      D4
//-------------------------------------------------------------
//  A8.  A0:    CS  0    Z  8     X  16    C 24    V 32
//  A9.  A1:    A   1    S  9     D  17    F 25    G 33     
//  A10. A2:    Q   2    W  10    E  18    R 26    T 34      
//  A11. A3:    1   3    2  11    3  19    4 27    5 35
//  A12. A4:    0   4    9  12    8  20    7 28    6 36
//  A13. A5:    P   5    O  13    I  21    U 29    Y 37
//  A14. A6:    Ent 6    L  14    K  22    J 30    H 38
//  A15. A7:    Sp  7    SS 15    M  23    N 31    B 39
//-------------------------------------------------------------
//  magic key:           40
//  Z80 reset:           41  
//-------------------------------------------------------------

module zxkeyboard (
    input wire clk_50M,   // external clock
    input wire [2:0] spi, // microcontroller SPI interface as [input data:clock:chip select]
    input wire [7:0] ka,  // address A8-A15
    input wire rst_i,     // reset input
    output wire [4:0] kd, // data D0-D4
    output wire rst_o,    // reset output
    output wire magic,    // magic button
    output wire led1,     // red led    
    output wire led2      // yellow led
);

reg [41:0] k; // keyboard state: 1-released, 0-pressed
reg [7:0] spi_data; // SPI data collector

//-------------------------------------------------------------
// reset, key state update
//-------------------------------------------------------------
always @(posedge clk_50M)
begin
    reg [5:0] key_bit_num;
    reg key_state;

    key_bit_num[5:0] = spi_data[5:0];
    key_state = !spi_data[6]; // set or reset state-bit
    
    if (rst_i == 1'd0) 
        k <= {42{1'b1}};                   // initialization on power on: set all bits
    else
        if (spi[0] == 1'd1)
        begin
            k[key_bit_num] <= key_state;   // set or clear state-bit
            if (key_bit_num == 41)
                k[40:0] = 41'h1FFFFFFFFFF; // cpu reset and initialization: set all bits except 'reset'
        end
end

//-------------------------------------------------------------
// SPI: CLK raise 
//-------------------------------------------------------------
always @(posedge spi[1])
begin
    if (spi[0] == 0) // chip select
    begin
        spi_data = spi_data >> 1;
        spi_data[7] = spi[2];
    end
end

assign kd[0]=(ka[0] | k[0 ]) & (ka[1] | k[1 ]) & (ka[2] | k[2 ]) & (ka[3] | k[3 ]) & (ka[4] | k[4 ]) & (ka[5] | k[5 ]) & (ka[6] | k[6 ]) & (ka[7] | k[7 ]);
assign kd[1]=(ka[0] | k[8 ]) & (ka[1] | k[9 ]) & (ka[2] | k[10]) & (ka[3] | k[11]) & (ka[4] | k[12]) & (ka[5] | k[13]) & (ka[6] | k[14]) & (ka[7] | k[15]);
assign kd[2]=(ka[0] | k[16]) & (ka[1] | k[17]) & (ka[2] | k[18]) & (ka[3] | k[19]) & (ka[4] | k[20]) & (ka[5] | k[21]) & (ka[6] | k[22]) & (ka[7] | k[23]);
assign kd[3]=(ka[0] | k[24]) & (ka[1] | k[25]) & (ka[2] | k[26]) & (ka[3] | k[27]) & (ka[4] | k[28]) & (ka[5] | k[29]) & (ka[6] | k[30]) & (ka[7] | k[31]);
assign kd[4]=(ka[0] | k[32]) & (ka[1] | k[33]) & (ka[2] | k[34]) & (ka[3] | k[35]) & (ka[4] | k[36]) & (ka[5] | k[37]) & (ka[6] | k[38]) & (ka[7] | k[39]);

assign rst_o = !k[41];
assign magic = k[40];

assign led1 = k[41];
assign led2 = k[40];

endmodule
