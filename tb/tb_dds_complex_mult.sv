module tb_dds_compiler_complex_mult;


  localparam PERIOD = 5;


  logic [15:0] tdata;
  logic tvalid;
  logic clk = 0;
  
  logic [1:0] data_in;
  logic data_in_valid;


  integer fileM;
  logic [7:0] byte_char;



 initial
  begin
    forever
      #(PERIOD/2)  clk=~clk;
  end



  dds_compiler_wrapper dut
                       (
                         .data_in_0 (data_in),
                         .data_in_valid_0 (data_in_valid),
                         .S_AXIS_CONFIG_0_tdata (16'd0),
                         .S_AXIS_CONFIG_0_tvalid (16'd0),
                         .S_AXIS_CONFIG_1_tdata (32'd0),
                         .S_AXIS_CONFIG_1_tvalid (1'd0),
                         .M_AXIS_DATA_0_tready(1'b1), 
                         .aclk_0(clk)
                       );
  integer i = 0;
  initial
  begin
  
    fileM = $fopen("/home/egoncu/Downloads/GNSS_SDR_C++/mat/GNSS_signal_records/NTLab_Bands_GPS_GLONASS_L12.bin", "r");
    while (i < 1024)
    begin
      i ++;
      byte_char = $fgetc(fileM);
      data_in = byte_char[1:0];
      data_in_valid = 1'b1;
      #(PERIOD);
    end
    data_in_valid = 1'b0;
  end  
   


  // initial
  // begin
  //     tdata = 0;
  //     tvalid = 0;
  //     #1000;

  //     tdata = 20;
  //     tvalid = 1;

  //     #10;
  //     tdata= 0;
  //     tvalid = 0;

  //     #1000;
  //     $finish();


  // end


endmodule
