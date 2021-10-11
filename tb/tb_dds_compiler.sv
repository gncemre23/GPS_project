module tb_dds_compiler;





  logic [15:0] tdata;
  logic tvalid;
  logic clk = 0;

  always @(*)
  begin
    clk = ~clk;
    #5;
  end

  dds_compiler_wrapper dut
                       (
                         .S_AXIS_PHASE_0_tdata (tdata),
                         .S_AXIS_PHASE_0_tvalid (tvalid),
                         .aclk_0(clk)
                       );


  initial
  begin
      tdata = 0;
      tvalid = 0;
      #1000;

      tdata = 20;
      tvalid = 1;

      #10;
      tdata= 0;
      tvalid = 0;

      #1000;
      $finish();


  end


endmodule
